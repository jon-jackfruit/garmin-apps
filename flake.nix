{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      forAll = f: nixpkgs.lib.genAttrs
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
        (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          shellHook = ''
            export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
            mkdir -p "$CLAUDE_CONFIG_DIR"
          '';
        };
      });
    };
}