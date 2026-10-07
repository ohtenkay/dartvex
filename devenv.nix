{ pkgs, ... }:

{
  packages = [ pkgs.flutter ];

  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_24;
    npm.enable = true;
  };
}
