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
                shellspec -c $src --format=progress
              '';
            };
          };

          devShells.default = pkgs.mkShell {
            name = "proxmox-upgrade-cluster-dev";

            buildInputs = with pkgs; [
              bash
              jq
              shellcheck
              shellspec
            ];
          };

        };
    };
}
