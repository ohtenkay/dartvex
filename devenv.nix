{ pkgs, ... }:

{
  android = {
    enable = true;
    flutter.enable = true;
    platforms.version = [ "35" "36" ];
    buildTools.version = [ "35.0.0" ];
    cmdLineTools.version = "22.0";
    ndk.version = [ "28.2.13676358" ];
    emulator.enable = false;
    systemImages.enable = false;
    googleAPIs.enable = false;
    googleTVAddOns.enable = false;
    extras = [ ];
  };

  languages.java.jdk.package = pkgs.jdk21;

  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_26;
    npm.enable = true;
  };
}
