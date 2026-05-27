{
  description = "Proxmox Upgrade Cluster development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          self',
          pkgs,
          lib,
          ...
        }:
        {
          packages = {
            default = self'.packages.proxmox-upgrade-cluster;
            proxmox-upgrade-cluster = pkgs.stdenvNoCC.mkDerivation {
              name = "proxmox-upgrade-cluster";
              src = ./.;

              nativeBuildInputs = with pkgs; [
                makeWrapper
                shfmt
              ];

              buildInputs = with pkgs; [
                bash
                jq
              ];

              installPhase = ''
                mkdir -p $out/bin

                cp $src/proxmox-upgrade-cluster.sh $out/bin/proxmox-upgrade-cluster
                chmod +x $out/bin/proxmox-upgrade-cluster
              '';

              checkPhase = ''
                # Format check first — a malformed script wouldn't behave the
                # way the tests expect anyway, so fail fast.
                shfmt -d -i 2 -ci $src/proxmox-upgrade-cluster.sh
                shellspec -c $src --format=progress
              '';
            };
          };

          devShells.default = pkgs.mkShell {
            name = "proxmox-upgrade-cluster-dev";

            buildInputs =
              (with pkgs; [
                bash
                jq
                shellcheck
                shellspec
                shfmt
              ])
              # kcov drives `shellspec --kcov` for line/branch coverage. The
              # upstream package only builds on Linux, so the dev shell on
              # darwin skips it — run coverage via CI or a Linux container.
              ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.kcov ];
          };

        };
    };
}
