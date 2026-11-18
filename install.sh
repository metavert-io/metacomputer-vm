#!/bin/bash
# install.sh: build mcomp-vm (if needed) and install it as `mcomp-vm`,
# next to any standard `lume` you have; both use the same VM storage.
#
#   ./install.sh               build if needed, install to ~/.local/share/mcomp-vm
#                              and ~/.local/bin/mcomp-vm
#   ./install.sh --uninstall   remove both (VMs are untouched)
set -Eeuo pipefail
cd "$(dirname "$0")"; ROOT="$PWD"
APP="$HOME/.local/share/mcomp-vm"
BIN="$HOME/.local/bin/mcomp-vm"
if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP" "$BIN"; echo "removed mcomp-vm (your VMs in ~/.lume are untouched)"; exit 0
fi
# Rebuild when the pin or a patch changed since the last build.
want="$(cat UPSTREAM patches/*.patch | shasum -a 256 | cut -d' ' -f1)"
if [ ! -x dist/mcomp-vm/lume ] || [ "$(cat dist/.inputs 2>/dev/null)" != "$want" ]; then
  ./build.sh
  echo "$want" > dist/.inputs
fi
rm -rf "$APP"; mkdir -p "$APP" "$HOME/.local/bin"
cp -R dist/mcomp-vm/. "$APP/"
cat > "$BIN" <<WRAP
#!/bin/sh
# mcomp-vm: Lume with opt-out host sharing (https://github.com/metavert-io/metacomputer-vm).
# Telemetry off; no background service is installed.
LUME_TELEMETRY_ENABLED=0 exec "$APP/lume" "\$@"
WRAP
chmod +x "$BIN"
echo "installed $BIN ($("$BIN" --version 2>/dev/null | head -1))"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "note: ~/.local/bin isn't on your PATH" ;; esac
