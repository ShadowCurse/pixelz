{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  SDL3_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.sdl3]}";
  buildInputs = with pkgs; [
    sdl3
  ];
}
