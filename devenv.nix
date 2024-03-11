{inputs, ...}: {
  perSystem = { pkgs, ... }:
  let gleam = inputs.gleam.packages.${pkgs.stdenv.system}.gleam; in
  {
    devenv.shells.default = {
      languages.erlang.enable = true;
      packages = [ gleam ];
    };
  };
}
