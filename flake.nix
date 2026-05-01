{
  description = "MIPaaS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }: 
    flake-utils.lib.eachDefaultSystem (system:
      let
          pkgs = import nixpkgs { inherit system; };
          julia = pkgs.julia-bin;

          src = pkgs.lib.cleanSource ./.;
      in {

        apps.dev-server = {
          type = "app";
          program = toString (pkgs.writeShellScript "mipaas-server" ''
            export JULIA_DEPOT_PATH="''${JULIA_DEPOT_PATH:-$HOME/.cache/mipaas-depot}"
            mkdir -p "$JULIA_DEPOT_PATH"
            ${julia}/bin/julia --project=${src}/server -e '
              using Pkg; Pkg.instantiate(); Pkg.precompile()
              include("${src}/server/src/Server.jl")
            '
          '');
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ 
            julia-bin 
            go

            fish 
          ];

          NIX_LD = "${pkgs.stdenv.cc.bintools.dynamicLinker}";
          NIX_LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
            stdenv.cc.cc.lib
            zlib
            gcc-unwrapped.lib
          ]);

          shellHook = ''
            exec fish -N -C "source scripts.fish; init"
          '';

      };
    });
}
