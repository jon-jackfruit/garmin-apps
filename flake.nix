{
  description = "Garmin Connect IQ development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The Connect IQ SDK manager and simulator are prebuilt binaries linked
    # against webkit2gtk-4.0 / libsoup-2.4, which were removed from later
    # nixpkgs (and from Ubuntu 24.04). 24.11 is the last release that has them.
    nixpkgs-ciq.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { nixpkgs, nixpkgs-ciq, ... }:
    let
      forAll = f: nixpkgs.lib.genAttrs
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
        (system: f system nixpkgs.legacyPackages.${system});
    in {
      devShells = forAll (system: pkgs:
        let
          inherit (pkgs) lib;
          isLinux = pkgs.stdenv.hostPlatform.isLinux;
          ciqPkgs = nixpkgs-ciq.legacyPackages.${system};

          # FHS sandbox with every library the Garmin binaries expect.
          # Usage: ciq-fhs <command> [args...]
          ciqFhs = ciqPkgs.buildFHSEnv {
            name = "ciq-fhs";
            targetPkgs = p: with p; [
              jdk17
              webkitgtk_4_0
              libsoup
              gtk3
              glib
              glib-networking
              gsettings-desktop-schemas
              cairo
              pango
              gdk-pixbuf
              atk
              libusb1
              libsecret
              libnotify
              libjpeg8
              libpng
              sqlite
              zlib
              freetype
              fontconfig
              dejavu_fonts
              alsa-lib
              pulseaudio
              mesa.drivers
              libglvnd
              librsvg
              shared-mime-info
              dbus
              xorg.libX11
              xorg.libXext
              xorg.libXrender
              xorg.libXtst
              xorg.libXi
              xorg.libXxf86vm
              xorg.libSM
              xorg.libICE
              expat
              wayland
              libxkbcommon
              openssl
              curl
              unzip
              which
              bash
              coreutils
            ];
            runScript = "bash -c 'exec \"$@\"' --";
            profile = ''
              export GIO_MODULE_DIR=/usr/lib/gio/modules
              # Point libglvnd/EGL at the sandbox's mesa (nothing at /run/opengl-driver on non-NixOS)
              export __EGL_VENDOR_LIBRARY_FILENAMES=${ciqPkgs.mesa.drivers}/share/glvnd/egl_vendor.d/50_mesa.json
              export LIBGL_DRIVERS_PATH=${ciqPkgs.mesa.drivers}/lib/dri
              export LIBVA_DRIVERS_PATH=${ciqPkgs.mesa.drivers}/lib/dri
              # Software GL by default: the pinned mesa may predate the host GPU.
              # Set CIQ_HW_GL=1 to try hardware acceleration instead.
              if [ -z "''${CIQ_HW_GL:-}" ]; then
                export LIBGL_ALWAYS_SOFTWARE=1
                export GALLIUM_DRIVER=llvmpipe
              fi
              # SVG/PNG icon loaders for GTK
              export GDK_PIXBUF_MODULE_FILE=${ciqPkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
              export XDG_DATA_DIRS="${ciqPkgs.shared-mime-info}/share:${ciqPkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${ciqPkgs.gsettings-desktop-schemas.name}:${ciqPkgs.gtk3}/share/gsettings-schemas/${ciqPkgs.gtk3.name}:''${XDG_DATA_DIRS:-/usr/share}"
              # webkit's GPU sandbox is unreliable outside a real FHS distro
              export WEBKIT_DISABLE_COMPOSITING_MODE=1
              export WEBKIT_DISABLE_DMABUF_RENDERER=1
            '';
          };

          sdkManagerDir = "\${XDG_DATA_HOME:-$HOME/.local/share}/connectiq-sdk-manager";

          # Downloads (once) and launches the Garmin SDK Manager.
          sdkmanager = pkgs.writeShellScriptBin "sdkmanager" ''
            set -euo pipefail
            dir="${sdkManagerDir}"
            if [ ! -x "$dir/bin/sdkmanager" ] || [ "''${1:-}" = "--update" ]; then
              echo "Downloading Connect IQ SDK Manager into $dir ..."
              tmp=$(mktemp -d)
              trap 'rm -rf "$tmp"' EXIT
              ${pkgs.curl}/bin/curl -fL -o "$tmp/sdkmanager.zip" \
                https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-linux.zip
              rm -rf "$dir"; mkdir -p "$dir"
              ${pkgs.unzip}/bin/unzip -q "$tmp/sdkmanager.zip" -d "$dir"
              [ "''${1:-}" = "--update" ] && shift
            fi
            exec ${ciqFhs}/bin/ciq-fhs "$dir/bin/sdkmanager" "$@"
          '';

          # Resolve the SDK selected in the SDK Manager ("Use as current SDK").
          ciqSdkPath = ''
            cfg="$HOME/.Garmin/ConnectIQ/current-sdk.cfg"
            if [ ! -f "$cfg" ]; then
              echo "No current SDK set. Run 'sdkmanager', install an SDK and click 'Use as current SDK'." >&2
              exit 1
            fi
            sdk="$(tr -d '\r\n' < "$cfg")"; sdk="''${sdk%/}"
          '';

          # Runs a tool from the current SDK's bin/ inside the FHS env.
          ciqTool = name: pkgs.writeShellScriptBin name ''
            set -euo pipefail
            ${ciqSdkPath}
            exec ${ciqFhs}/bin/ciq-fhs "$sdk/bin/${name}" "$@"
          '';

          # Simulator: start this before "Run App" in VS Code; the extension
          # connects to an already-running simulator.
          ciqSim = pkgs.writeShellScriptBin "ciq-sim" ''
            set -euo pipefail
            ${ciqSdkPath}
            exec ${ciqFhs}/bin/ciq-fhs "$sdk/bin/simulator" "$@"
          '';

          # One-off: create the signing key every Connect IQ build needs.
          ciqKeygen = pkgs.writeShellScriptBin "ciq-keygen" ''
            set -euo pipefail
            out="''${1:-$HOME/.Garmin/developer_key.der}"
            if [ -e "$out" ]; then echo "$out already exists, not overwriting." >&2; exit 1; fi
            mkdir -p "$(dirname "$out")"
            ${pkgs.openssl}/bin/openssl genrsa 4096 \
              | ${pkgs.openssl}/bin/openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -out "$out"
            chmod 600 "$out"
            echo "Developer key written to $out (back it up: apps signed with it can only be updated with it)."
          '';
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.jdk17 pkgs.openssl ciqKeygen ]
              ++ lib.optionals isLinux ([ ciqFhs sdkmanager ciqSim ]
                ++ map ciqTool [ "monkeyc" "monkeydo" "connectiq" "barrelbuild" "era" ]);

            shellHook = ''
              export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
              mkdir -p "$CLAUDE_CONFIG_DIR"
              export JAVA_HOME="${pkgs.jdk17}"
              export CIQ_DEVELOPER_KEY="$HOME/.Garmin/developer_key.der"
            '';
          };
        });
    };
}
