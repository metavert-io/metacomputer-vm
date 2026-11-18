# mcomp-vm

mcomp-vm is [Lume](https://github.com/trycua/cua/tree/main/libs/lume), Cua's
macOS VM runner on Apple's Virtualization framework, with one addition:
flags that leave out the devices connecting a VM to your Mac's clipboard,
audio and Rosetta.

It's [metacomputer](https://github.com/metavert-io/metacomputer)'s build of
Lume, made by Metavert, not by Cua, and not endorsed by them. The name Lume
appears here only to say what mcomp-vm is built from.

## The flags

Lume attaches three host-sharing devices to every VM. mcomp-vm keeps that
default and adds a flag to leave out each one:

| Flag | Leaves out | What it shares |
| --- | --- | --- |
| `--no-share-clipboard` | the SPICE agent console port | your Mac's clipboard, both ways, with any guest agent |
| `--no-share-audio` | the virtio sound device | your Mac's speakers **and microphone** |
| `--no-share-rosetta` | the Rosetta directory share (Linux guests) | Apple's Rosetta translator |
| `--no-host-sharing` | all three | |

```bash
mcomp-vm run my-vm --no-host-sharing          # isolated from the host
mcomp-vm run my-vm --no-share-clipboard       # just no clipboard sharing
mcomp-vm run my-vm                            # Lume's defaults: all three shared
```

**Why.** Inside a guest, any process with root can start a SPICE agent and
read or set your Mac's clipboard, or open the sound device and listen to the
microphone. A guest that runs untrusted software (a browser, downloads, an
AI agent's tasks) shouldn't have those paths at all. metacomputer runs its
VM with `--no-host-sharing` unless the user turns a device on.

A VM suspended with different devices can't resume from that saved state,
so it boots instead.

Everything else is Lume's: the other commands, the `serve` API, the VM
storage in `~/.lume`, the settings file and the `LUME_*` environment
variables. Only the name and version it shows are its own (the help banner,
usage lines, `--version` and the VM window's title).

## Install

Needs an Apple-silicon Mac, git, and Swift (Apple's Command Line Tools:
`xcode-select --install`).

```bash
git clone https://github.com/metavert-io/metacomputer-vm.git
cd metacomputer-vm
./install.sh            # builds (about a minute) and installs ~/.local/bin/mcomp-vm
```

It installs as its own command, `mcomp-vm`, next to any standard `lume`;
both use the same VM storage (`~/.lume`). The `mcomp-vm` command turns
Lume's telemetry off, and no background service is installed.
`./install.sh --uninstall` removes it and leaves your VMs alone.

You don't need these steps for metacomputer: its installer installs mcomp-vm
automatically, from a pinned tag of this repository.

## How it's made

This repository holds no copy of Lume, only:

| File | Contents |
| --- | --- |
| `UPSTREAM` | the Lume release it builds from (tag and exact commit) and mcomp-vm's revision |
| `patches/` | the changes, as readable patches, each with unit tests |
| `build.sh` | clones that tag, refuses any other commit, applies the patches, runs `swift build`, signs, and checks the result |

The patches:

- `0001-run-host-sharing-flags.patch`: the flags above.
- `0002-mcomp-vm-name-and-version.patch`: the name and version the binary
  shows (`mcomp-vm` and `0.7.2-mcomp.2`), with no change to its storage,
  settings, environment variables or API.

The binary is signed locally (ad hoc) with Lume's own virtualization
entitlement, the way Lume's `install-local.sh` builds it.

## Versions

A version is the Lume version, then `-mcomp.` and mcomp-vm's revision:
**0.7.2-mcomp.2** is Lume 0.7.2 with this repository's two patches, tagged
`v0.7.2-mcomp.2`. The revision goes up with every release.

`mcomp-vm --version` prints the version. `BUILD_INFO` in the install folder
(`~/.local/share/mcomp-vm`) records it, with the Lume tag and commit and a
checksum of each patch.

## License

MIT ([LICENSE](LICENSE)): the patches and scripts are © Metavert LLC. Lume
is © Cua AI, Inc., under the MIT license in [NOTICE](NOTICE).
