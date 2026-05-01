{
  description = "MIPaaS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?nixos-25.11";
  };

  outputs = { self, nixpkgs }: 
    let
      # define system once
      system = "x86_64-linux";
      # use it here, and bind platform-specific packages to `pkgs`
      pkgs = nixpkgs.legacyPackages.${system};
    in {

    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [ 
        julia-bin 
        fish 
      ];

      NIX_LD = "${pkgs.stdenv.cc.bintools.dynamicLinker}";
      NIX_LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
        stdenv.cc.cc.lib
        zlib
        gcc-unwrapped.lib
      ]);

      APPLICATION = "NEM Explore";
      shellHook = ''
        exec fish -N -C "source scripts.fish; init"
      '';

    };
  };

}
