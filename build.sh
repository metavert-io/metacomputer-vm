#!/bin/bash
# build.sh: build mcomp-vm = the Lume release pinned in UPSTREAM + patches/.
#
#   ./build.sh          -> dist/mcomp-vm/ (the lume binary and its resource bundle,
#                          ad-hoc signed with Lume's own virtualization entitlement)
#   ./build.sh --test   the same, after running the unit tests the patches add
#                       (swift test in the patched source)
#
# It clones exactly the pinned tag, refuses anything but the pinned commit,
# applies every patch in order (failing if one doesn't apply cleanly), builds
# with SwiftPM, signs, and checks that the result runs, reports the expected
# version (LUME_VERSION-mcomp.MCOMP_REVISION) and has the new flags.
# Needs git and Swift (Apple's Command Line Tools: xcode-select --install).
set -Eeuo pipefail
cd "$(dirname "$0")"; ROOT="$PWD"
die() { printf 'build: %s\n' "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR
TEST=
case "${1:-}" in --test) TEST=1 ;; "") ;; *) die "usage: ./build.sh [--test]" ;; esac
# shellcheck source=UPSTREAM
. ./UPSTREAM
command -v git >/dev/null || die "git is needed"
command -v swift >/dev/null || die "Swift is needed: install Apple's Command Line Tools (xcode-select --install)"

WORK="$(mktemp -d /tmp/mcomp-vm.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
echo "==> Lume $UPSTREAM_TAG ($UPSTREAM_COMMIT)"
git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$WORK/src"
got="$(git -C "$WORK/src" rev-parse HEAD)"
[ "$got" = "$UPSTREAM_COMMIT" ] || die "$UPSTREAM_TAG is $got, not the pinned $UPSTREAM_COMMIT"
git -C "$WORK/src" sparse-checkout set libs/lume
git -C "$WORK/src" checkout -q

for p in "$ROOT"/patches/*.patch; do
  echo "==> applying $(basename "$p")"
  git -C "$WORK/src" apply --check "$p" || die "$(basename "$p") doesn't apply to $UPSTREAM_TAG"
  git -C "$WORK/src" apply "$p"
done

if [ -n "$TEST" ]; then
  # The tests the patches add: top-level test functions and suites in their test files.
  names="$(awk '/^\+\+\+ /{t = ($2 ~ /^b\/libs\/lume\/tests\//); next}
    t && match($0, /^\+(func|struct) [A-Za-z0-9_]+/) {s = substr($0, 2, RLENGTH - 1); sub(/^[a-z]+ /, "", s); print s}' \
    "$ROOT"/patches/*.patch | paste -sd'|' -)"
  [ -n "$names" ] || die "the patches add no unit tests"
  echo "==> swift test: the patches' unit tests"
  (cd "$WORK/src/libs/lume" && swift test --filter "\.($names)[(/]")
fi

echo "==> swift build -c release (about a minute)"
(cd "$WORK/src/libs/lume" && swift build -c release --product lume)
B="$WORK/src/libs/lume/.build/release"
OUT="$ROOT/dist/mcomp-vm"
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$B/lume" "$OUT/lume"
[ -d "$B/lume_lume.bundle" ] && cp -R "$B/lume_lume.bundle" "$OUT/"
codesign --force --identifier io.metavert.mcomp-vm \
  --entitlements "$WORK/src/libs/lume/resources/lume.local.entitlements" --sign - "$OUT/lume"

export LUME_TELEMETRY_ENABLED=0   # the checks below run the binary; keep them silent
VERSION="$LUME_VERSION-mcomp.$MCOMP_REVISION"
got="$("$OUT/lume" --version)" || die "the built binary doesn't run"
[ "$got" = "$VERSION" ] || die "the built binary says $got, not $VERSION: check LUME_VERSION and MCOMP_REVISION in UPSTREAM against the source and MCompVM.revision in patches/0002"
"$OUT/lume" run --help 2>&1 | grep -q -- "--no-host-sharing" || die "the built binary lacks the host-sharing flags"
{
  echo "version=$VERSION"
  echo "lume_version=$LUME_VERSION"
  echo "mcomp_revision=$MCOMP_REVISION"
  echo "upstream=$UPSTREAM_TAG $UPSTREAM_COMMIT"
  for p in "$ROOT"/patches/*.patch; do echo "patch=$(basename "$p") $(shasum -a 256 "$p" | cut -d' ' -f1)"; done
} > "$OUT/BUILD_INFO"
echo "==> built dist/mcomp-vm: mcomp-vm $VERSION (Lume $LUME_VERSION + patches)"
