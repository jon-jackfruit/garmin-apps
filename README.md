# garmin-apps

Garmin Connect IQ apps, developed on Linux with a Nix flake dev shell.

## Nix setup

The dev shell is defined in `flake.nix` and loaded automatically by direnv (`.envrc` → `use flake`).

```sh
direnv allow        # first time only
direnv reload       # after editing flake.nix
nix develop         # alternative if you're not using direnv
```

The Connect IQ SDK isn't in nixpkgs: it's proprietary and installed through Garmin's SDK Manager, which needs a Garmin account. The flake doesn't package the SDK. It provides a runtime for Garmin's prebuilt binaries:

- **Two nixpkgs inputs.** `nixpkgs` (unstable) supplies normal tooling such as JDK 17 and openssl. `nixpkgs-ciq` is pinned to **nixos-24.11** because the SDK Manager and simulator link against `webkit2gtk-4.0` and `libsoup-2.4`. Ubuntu 24.04 and current nixpkgs have dropped both, and 24.11 is the last release that has them.
- **`ciq-fhs` sandbox.** A `buildFHSEnv` built from `nixpkgs-ciq` that contains every library the Garmin binaries need. The wrapper commands below run the binaries inside it, so nothing depends on system libraries.
- **Software rendering.** Graphics use mesa's llvmpipe by default because the pinned mesa may predate the host GPU. Set `CIQ_HW_GL=1` to try hardware acceleration.

Files outside the repo:

| Path | Contents |
|---|---|
| `~/.local/share/connectiq-sdk-manager/` | SDK Manager, downloaded on first run |
| `~/.Garmin/ConnectIQ/` | SDKs and device files installed by the SDK Manager; `current-sdk.cfg` selects the active SDK |
| `~/.Garmin/developer_key.der` | Signing key (`$CIQ_DEVELOPER_KEY`) |

## Commands

All of these are on `PATH` inside the dev shell.

| Command | What it does |
|---|---|
| `sdkmanager` | Downloads the SDK Manager on first run, then launches it. `sdkmanager --update` downloads it again. |
| `ciq-sim` | Starts the Connect IQ simulator from the current SDK |
| `monkeyc` | Monkey C compiler (current SDK) |
| `monkeydo` | Runs a built `.prg` in the running simulator |
| `connectiq` | Garmin's own simulator launcher script |
| `barrelbuild` | Builds Monkey Barrels (libraries) |
| `era` | Error Reporting App: fetches crash reports for published apps |
| `ciq-keygen [path]` | Creates the developer signing key (default `~/.Garmin/developer_key.der`) and refuses to overwrite an existing one |
| `ciq-fhs <cmd> ...` | Runs any command inside the sandbox, useful for debugging (e.g. `ciq-fhs ldd <binary>`) |

The SDK tools (`monkeyc`, `ciq-sim`, etc.) always use the SDK selected with **Use as current SDK** in the SDK Manager.

## First-time setup

1. Run `sdkmanager`, sign in, install the latest SDK, click **Use as current SDK**, and download the device files for your watch.
2. Run `ciq-keygen` once. **Back up the key:** a published app can only be updated if it's signed with the same key.
3. Install the VS Code extensions:
   ```sh
   code --install-extension garmin.monkey-c      # Monkey C language, build, run, debug
   code --install-extension mkhl.direnv          # loads this flake's env into VS Code
   code --install-extension jnoortheen.nix-ide   # optional, for editing flake.nix
   ```
4. In VS Code, run **Monkey C: Verify Installation** and point it at `~/.Garmin/developer_key.der`.

## Day-to-day

**From VS Code:** start `ciq-sim` in a terminal first, then use **Run App** / **Debug**. The extension connects to the simulator that's already running. If it launches the simulator itself, the simulator runs outside the sandbox and fails to find its libraries.

**From the command line:**

```sh
ciq-sim &
monkeyc -f monkey.jungle -d <device> -y "$CIQ_DEVELOPER_KEY" -o bin/app.prg
monkeydo bin/app.prg <device>
```

`<device>` is a device id such as `fr965` or `fenix7`. The ids are listed in `manifest.xml` and in `~/.Garmin/ConnectIQ/Devices/`.

Build an `.iq` package for the Connect IQ store with `monkeyc -e -f monkey.jungle -y "$CIQ_DEVELOPER_KEY" -o bin/app.iq`.

## Troubleshooting

- **Blank login/web window, or `EGL_BAD_PARAMETER`:** EGL can't find a graphics driver. Check that `ciq-fhs bash -c 'echo $__EGL_VENDOR_LIBRARY_FILENAMES'` prints a path.
- **Wayland issues:** try `GDK_BACKEND=x11 sdkmanager` (or `ciq-sim`).
- **`cannot open shared object file`:** run `ciq-fhs ldd <binary> | grep "not found"` and add the missing library to `targetPkgs` in `flake.nix`.
- **Slow simulator:** try `CIQ_HW_GL=1 ciq-sim`.
