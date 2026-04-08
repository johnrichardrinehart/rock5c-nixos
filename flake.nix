{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          formatter = pkgs.nixfmt-rfc-style;
          packages = import ./packages { inherit pkgs; };
          checks = import ./checks.nix {
            inherit inputs pkgs system;
            rock5cModules = self.nixosModules;
          };
        };

      flake = {
        overlays.default = import ./overlays/default.nix;
        nixosModules = import ./nixosModules;
        homeManagerModules = import ./homeManagerModules;
      };
    };
}
