{
  description = "mwengine build dev shell";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_15
            pkgs.libx11
            pkgs.vulkan-loader
            pkgs.vulkan-validation-layers
            pkgs.vulkan-tools
            pkgs.glslang
            pkgs.git
          ];

          LD_LIBRARY_PATH = "${nixpkgs.lib.makeLibraryPath [
            pkgs.kdePackages.wayland
            pkgs.libxkbcommon
            pkgs.libGL
          ]}";

          shellHook = ''
            echo Entering Dev Shell
            echo Zig Version: $(zig version)
            echo ""
          '';
        };

      }
    );
}
