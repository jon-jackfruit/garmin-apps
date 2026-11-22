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

- **Two nixpkgs inputs.** `nixpkgs` (unstable) supplies normal tooling such as JDK 17, openssl, Node.js 24 and pnpm. `nixpkgs-ciq` is pinned to **nixos-24.11** because the SDK Manager and simulator link against `webkit2gtk-4.0` and `libsoup-2.4`. Ubuntu 24.04 and current nixpkgs have dropped both, and 24.11 is the last release that has them.
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
| `ciq-patch-sdk` | Replaces each installed SDK's `bin/simulator` with a wrapper that runs it in the sandbox, so VS Code can launch it. `--undo` reverts it. |
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
4. Run `ciq-patch-sdk` so VS Code can start the simulator itself. **Re-run it after installing a new SDK.**
5. In VS Code, run **Monkey C: Verify Installation** and point it at `~/.Garmin/developer_key.der`.

## Day-to-day

**From VS Code:** use **Run Without Debugging** / **Start Debugging**. The extension connects to a running simulator or launches `<sdk>/bin/simulator` itself. The extension has no setting for the simulator path, and outside the sandbox that binary can't find `webkit2gtk-4.0`. `ciq-patch-sdk` fixes this by moving the real binary to `simulator.real` and putting a wrapper in its place. The wrapper uses a GC-rooted link at `~/.local/state/connectiq/ciq-fhs`, so it survives `nix-collect-garbage`. Re-run `ciq-patch-sdk` after changing `flake.nix`.

**From the command line (pnpm scripts):**

Run `pnpm install` once after cloning; there are no dependencies, but it sets up the workspace. The scripts are thin wrappers around `scripts/ciq.mjs`:

| Script | What it does |
|---|---|
| `pnpm start [app] [-d device]` | Builds the app, starts the simulator if it isn't running, and loads the app. It stays attached and shows `System.println` output; press Ctrl-C to detach, and the simulator keeps running. |
| `pnpm build [app] [-d device]` | Builds `<app>/bin/<app>.prg` |
| `pnpm sim` | Starts the simulator in the background (a no-op if it's already running) |
| `pnpm package [app]` | Builds the store package `<app>/bin/<app>.iq` for every device in the manifest (release build) |
| `pnpm devices [app]` | Lists the devices in the app's `manifest.xml` |
| `pnpm apps` | Lists the apps in the repo |
| `pnpm clean [app]` | Deletes `<app>/bin` |

- **App:** `[app]` is an app directory such as `watch-face-01`. If you leave it out, it's the app you're currently inside (any subdirectory works) or the only app in the repo.
- **Device:** `-d` defaults to the first `<iq:product>` in `manifest.xml`.
- **Extra compiler flags:** anything after `--` goes to `monkeyc`, e.g. `pnpm build -- -g` for a debug build.

Examples:

```sh
pnpm start                          # build + run the only/current app on its first device
pnpm start watch-face-01 -d fr165m  # specific app and device
pnpm package watch-face-01          # store package
```

**Raw SDK commands**, if you need them, run from the app directory:

```sh
ciq-sim &
monkeyc -f monkey.jungle -d <device> -y "$CIQ_DEVELOPER_KEY" -o bin/app.prg
monkeydo bin/app.prg <device>     # wait until the simulator window is up first
```

`<device>` is a device id such as `fr965` or `fenix7`. The ids are listed in `manifest.xml` and in `~/.Garmin/ConnectIQ/Devices/`.

The simulator runs inside a bubblewrap sandbox started with `--die-with-parent`, so it exits when the shell or process that started it exits. `pnpm sim` and `pnpm start` work around this by giving it its own detached parent process.

## Troubleshooting

- **Blank login/web window, or `EGL_BAD_PARAMETER`:** EGL can't find a graphics driver. Check that `ciq-fhs bash -c 'echo $__EGL_VENDOR_LIBRARY_FILENAMES'` prints a path.
- **Wayland issues:** try `GDK_BACKEND=x11 sdkmanager` (or `ciq-sim`).
- **`cannot open shared object file`:** run `ciq-fhs ldd <binary> | grep "not found"` and add the missing library to `targetPkgs` in `flake.nix`.
- **VS Code: `Unable to connect to simulator`:** the SDK isn't patched (new SDK installed?). Run `ciq-patch-sdk`, or start `ciq-sim` before running.
- **Slow simulator:** try `CIQ_HW_GL=1 ciq-sim`.
