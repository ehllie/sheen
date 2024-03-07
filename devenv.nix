{
  perSystem = { pkgs, ... }: {
    devenv.shells.default = {
      languages.erlang.enable = true;
      packages = [ pkgs.gleam ];
    };
  };
}
