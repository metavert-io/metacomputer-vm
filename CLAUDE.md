# mcomp-vm: notes for maintainers

## What this repository is

mcomp-vm is metacomputer's build of Lume, Cua's macOS VM runner
(`libs/lume` in github.com/trycua/cua). It's kept as a pinned upstream
release plus patches:

- **There is no Lume source here.** `build.sh` clones the pinned Lume commit
  into a temporary folder, applies `patches/`, builds and signs. Every change
  to Lume is a patch in `patches/`; never vendor or copy Lume's source into
  this repository.
- It changes two things. `0001` adds `run --no-share-clipboard`,
  `--no-share-audio`, `--no-share-rosetta` and `--no-host-sharing` (Lume's
  default sharing is unchanged). `0002` makes the binary show its own name
  and version: `mcomp-vm` in usage lines, help and the VM window's title,
  and `--version` = `<Lume version>-mcomp.<revision>`.
- Everything else stays Lume's, and users depend on it: the `~/.lume` VM
  storage, the settings file (`~/.config/lume/config.yaml`), the `LUME_*`
  environment variables, the `lume serve` API, `Lume.Version.current` (the
  API, the update check and telemetry report it), and the binary's file
  name, `lume`, inside the install folder, which the wrapper runs. (Lume
  also reads its own file name to pick a channel: `lume-local` would switch
  it to a separate home.)

## Layout

| Path | What it is |
| --- | --- |
| `UPSTREAM` | the Lume release (repository, tag, exact commit, version) and `MCOMP_REVISION`; sourced by `build.sh` |
| `patches/` | `000N-*.patch`, applied in order; each adds its unit tests |
| `build.sh` | clone the tag, refuse any other commit, apply the patches, optionally run their tests, `swift build -c release`, ad-hoc sign with Lume's `lume.local.entitlements`, check the binary, write `BUILD_INFO` |
| `install.sh` | build if `UPSTREAM` or a patch changed (`dist/.inputs`), copy to `~/.local/share/mcomp-vm`, write the `~/.local/bin/mcomp-vm` wrapper; `--uninstall` removes both |
| `scripts/check-public.sh` | pre-publication check, a copy of a shared script: replace it with a newer copy, don't edit it here |
| `NOTICE` | Lume's MIT license notice |
| `LICENSE` | MIT, Metavert LLC |
| `dist/` | build output, gitignored; never commit it |

## Build and test

```bash
./build.sh            # dist/mcomp-vm/: lume, lume_lume.bundle, BUILD_INFO
./build.sh --test     # the same, after running the patches' unit tests
```

Both need the network (the Lume clone and SwiftPM's dependencies) and Swift
from Apple's Command Line Tools. A build takes about two minutes; `--test`
adds about a minute.

`--test` runs `swift test` in the patched source, filtered to the tests the
patches add: the top-level `@Test` functions and `@Suite` structs in the test
files the patches touch under `libs/lume/tests/`. A new patch's tests go in a
new test file in one of those two forms, or `--test` won't find them. It
doesn't run Lume's whole suite: some of those tests use the real
`~/.config/lume` settings and `~/.lume` (Foundation ignores `$HOME`), so run
the whole suite only on a Mac whose Lume setup you can afford to disturb.

`build.sh` already fails unless `--version` is exactly
`$LUME_VERSION-mcomp.$MCOMP_REVISION` and `run --help` lists
`--no-host-sharing`. To look at the binary yourself (all read-only):

```bash
export LUME_TELEMETRY_ENABLED=0
dist/mcomp-vm/lume --version        # 0.7.2-mcomp.2
dist/mcomp-vm/lume run --help       # banner, "USAGE: mcomp-vm run ...", the --no-share-* flags
dist/mcomp-vm/lume ls               # lists the VMs in ~/.lume
cat dist/mcomp-vm/BUILD_INFO
```

Don't run `install.sh` on someone's Mac unless they ask: it replaces the
runner their VMs use.

### Working on a patch

```bash
. ./UPSTREAM
W=$(mktemp -d)
git clone --filter=blob:none --no-checkout --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$W"
git -C "$W" sparse-checkout set libs/lume && git -C "$W" checkout -q
git -C "$W" -c user.name="Metavert LLC" -c user.email=jon@metavert.io \
  am "$PWD"/patches/*.patch         # one commit per patch
# edit, test (cd "$W/libs/lume" && swift test --filter ...), amend that patch's commit, then
# write it back in the same form as the others (no "From <sha>" or Date line):
git -C "$W" format-patch -1 --stdout --no-signature <commit> \
  | sed -e '1{/^From [0-9a-f]\{40\} /d;}' -e '/^Date: /d' > patches/000N-name.patch
```

Patch commits are authored `Metavert LLC <jon@metavert.io>`, with a subject
and a short body saying what changes and what doesn't.

## Moving to a new Lume release

1. Find the release tag (`lume-vX.Y.Z`) and its commit:
   `git ls-remote https://github.com/trycua/cua.git 'refs/tags/lume-vX.Y.Z*'`
   (for an annotated tag, the commit is the `^{}` line).
2. Check the license at that commit: the repository's `LICENSE.md` is MIT
   (Cua AI, Inc.), and nothing under `libs/lume` says otherwise (no license
   file of its own, no FSL). If that changed, stop and ask before building
   on it. Update `NOTICE` if Lume's notice changed.
3. Re-pin `UPSTREAM`: `UPSTREAM_TAG`, `UPSTREAM_COMMIT`, and `LUME_VERSION`
   (`libs/lume/VERSION` at that commit).
4. Rebase the patches: `am -3` them in a clone of the new tag (as in
   "Working on a patch"), resolve conflicts, and write each patch back.
5. Bump `MCOMP_REVISION` in `UPSTREAM` and `MCompVM.revision` in
   `patches/0002-mcomp-vm-name-and-version.patch` to the same number. The
   revision goes up by one with every release (a new Lume version or a
   change to a patch) and never resets, so every tag is unique.
6. `./build.sh --test`, then check the binary as above.
7. Update the version numbers in `README.md` (and here, in the examples).
8. `scripts/check-public.sh -a`: 0 findings.
9. Commit on a branch and open a pull request. Once it's merged, tag the
   merge commit on `main`, `git tag -a v<lume>-mcomp.<n> -m "mcomp-vm <lume>-mcomp.<n>"`,
   and push the tag.
10. Update metacomputer (next section).

## The release contract with metacomputer

metacomputer pins this repository in its `config/defaults.env`:
`MCOMP_VM_REPO`, `MCOMP_VM_TAG` and `MCOMP_VM_COMMIT`. Its installer clones
`MCOMP_VM_TAG`, refuses any commit other than `MCOMP_VM_COMMIT`, and runs
this repository's `install.sh`.

- After tagging here, open a pull request in metavert-io/metacomputer that
  updates both `MCOMP_VM_TAG` and `MCOMP_VM_COMMIT`. The commit is the
  tagged commit, `git rev-parse v<lume>-mcomp.<n>^{commit}`, not the
  annotated tag object. If the Lume version changed, say whether
  metacomputer's own Lume pins should move too.
- Never move or delete a pushed tag: every installer pinned to it would
  refuse the new commit. Fix forward with a new revision.
- metacomputer relies on these, so keep them working: `BUILD_INFO`'s
  `upstream=lume-v<version> <commit>` line; `run --help` listing
  `--no-host-sharing`; `--version` output containing the Lume version
  (`0.7.2`); the wrapper `~/.local/bin/mcomp-vm` and the install folder
  `~/.local/share/mcomp-vm` with the binary named `lume` inside.
- Check how metacomputer's installer decides an existing install is current.
  It compares `BUILD_INFO`'s `upstream=` line, so a release that changes
  only the revision doesn't replace an existing install unless that check
  also reads `version=`. Mention it in the metacomputer pull request.

## Naming

- The product, its command, repository, tags and packages are mcomp-vm.
  Never give any of them a Lume-based name: Cua's trademark policy asks a
  modified version to use another name.
- Saying what it's built from is fine: "metacomputer's build of Lume",
  "based on Lume", "Lume 0.7.2 plus patches". Keep "made by Metavert, not by
  Cua, and not endorsed by them" in the README, and don't use Cua's or
  Lume's logos.
- Lume's names in internals (`~/.lume`, `LUME_*`, the `lume` file name, the
  `Lume` Swift types, Lume's own messages that suggest `lume <command>`)
  stay: they're compatibility, not branding.

## Licensing

- MIT (`LICENSE`, Metavert LLC). Keep `NOTICE`, which carries Lume's MIT
  notice; Lume is © Cua AI, Inc.
- Never copy code from the FSL-licensed parts of trycua/cua: some crates
  under `libs/cua` are FSL-1.1-MIT. Patches touch `libs/lume` only.
- At every new pin, check that Lume itself (`libs/lume`) is still MIT (step 2
  above).

## Publishing

- Before every push, `scripts/check-public.sh -a` must report 0 findings.
  Run it on its own, not piped into `tail` or `grep`, and gate on its exit
  code. It also runs gitleaks when it's installed.
- Commit as jon@metavert.io (`git config user.email jon@metavert.io` in this
  repository).
- Telemetry stays off: the `mcomp-vm` wrapper that `install.sh` writes sets
  `LUME_TELEMETRY_ENABLED=0`, and `build.sh` sets it for its checks. Don't
  install a background service (LaunchAgent) either.
