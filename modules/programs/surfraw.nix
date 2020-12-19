{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.surfraw;

  reservedSettings = {
    graphical = "useGraphicalBrowser";
    graphical_browser = "graphical.browser";
    graphical_browser_args = "graphical.browserArgs";
    text_browser = "textual.browser";
    text_browser_args = "textual.browserArgs";
  };

  configOptionsAsSettings = mapAttrs 
    (n: opt: getAttrFromPath (splitString "." opt) cfg.config) reservedSettings;

  settingsToConfigLines = settings: let
    mkKeyString = key: "SURFRAW_${key}";
    mkValueString = value:
      if value == true then "yes"
      else if value == false then "no"
      else if isList value && (toString value) == "" then "none"
      else if isList value then ''"${toString value}"''
      else if isString value then value
      else toString value;
    mkConfigString = key: value: "${mkKeyString key}=${mkValueString value}";
  in mapAttrsToList mkConfigString settings;

  configText = let 
    configLines = settingsToConfigLines (cfg.settings // configOptionsAsSettings);
    collisions = intersectLists (attrNames cfg.settings) (attrNames reservedSettings);
    collisionCheck = asserts.assertMsg (collisions == []) ''
      Some surfraw.settings options conflict with some surfraw.config options. 
      To resolve this conflicts, you should:
      ${concatMapStringsSep "\n" collisionResolveDescription collisions}'';
    collisionResolveDescription = opt:
      "replace settings.${opt} with config.${getAttr opt reservedSettings}";
  in assert collisionCheck; concatStringsSep "\n" configLines;
in {
  options.programs.surfraw = {
    enable = mkEnableOption 
      "surfraw - a fast unix command line interface to WWW services";

    config = mkOption {
      default = {};
      description = "Surfraw configuration options.";
      type = types.submodule {
        options = {
          useGraphicalBrowser = mkOption {
            default = true;
            description = "Whether to use the graphical or textual browser.";
          };
          
          graphical = mkOption {
            description = "Configuration options for the graphical browser.";
            default = {};
            type = types.submodule {
              options = {
                browser = mkOption {
                  type = types.str;
                  description = "Name/path of the graphical browser executable.";
                  example = literalExample "${pkgs.firefox}/bin/firefox";
                  default = "${pkgs.firefox}/bin/firefox";
                };

                browserArgs = mkOption {
                  type = types.listOf types.str;
                  description = "Cmdline arguments given to the browser.";
                  example = literalExample ''["-console"]'';
                  default = [""];
                };
              };
            };
          };

          textual = mkOption {
            description = "Configuration options for the textual browser.";
            default = {};
            type = types.submodule {
              options = {
                browser = mkOption {
                  type = types.str;
                  description = "Name/path of the text browser executable.";
                  example = literalExample ''\${pkgs.links}/bin/w3m'';
                  default = "${pkgs.w3m}/bin/w3m";
                };

                browserArgs = mkOption {
                  type = types.listOf types.str;
                  description = "Cmdline arguments given to the browser.";
                  example = literalExample ''["-dump"]'';
                  default = [""];
                };
              };
            };
          };
        };
      };
    };

    settings = mkOption {
      type = with types; attrsOf (oneOf [str bool int]);
      description = ''
        Additional configuration options added to surfraw configuration file
        <filename>$HOME/.config/surfraw/conf</filename>, as seen in the 
        man pages (without the 'SURFRAW_' prefix.
      '';
      example = literalExample ''
        {
          graphical_remote = false;
          escape_url_args = true;
          results = 15;
          ...
        }
      '';
      default = {};
    };

    addElviToPath = mkEnableOption ''Adds the surfraw elvi directory to PATH. 
      Then the elvis can be invoked without calling surfraw.
      Attention: This change takes effect after a relogin.'';

    addElvi = mkOption {
      type = with types; either path (listOf path);
      description = ''Additional elvi to be installed to the user elvi directory'';
      example = literalExample ''./data/elvi or [ ./data/elvi/duckduckgo ]'';
      default = [];
    };

    addBookmark = mkOption {
      default = {};
      description = "Options for the bookmark file usage.";
      type = types.submodule {
        options = {
          file = mkOption {
            type = types.nullOr types.path;
            description = ''Path to the bookmark file to use.'';
            example = literalExample ''./my-bookmarks'';
            default = null;
          };
          toStore = mkEnableOption ''Whether to place a symlink of to the 
            bookmark file or the file itself in the nix-store.
            NOTE: Files in the nix-store are readable by other users and
            changes to the bookmark file require a home-manager switch.
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.surfraw ];
    home.sessionPath = [ 
      (mkIf cfg.addElviToPath "${pkgs.surfraw}/lib/surfraw")
    ];

    xdg.configFile."surfraw/elvi" = let
      elvis = let 
        mkEntry = elvi: {
          name = if isDerivation elvi 
            then strings.getName elvi 
            else baseNameOf elvi;
          path = elvi;
        };
      in map mkEntry cfg.addElvi;
    in mkIf (cfg.addElvi != []) {
      source = if isList cfg.addElvi
        then pkgs.buildPackages.linkFarm "surfraw-elvis" elvis
        else cfg.addElvi;
    };

    # This will place a symlink of the bookmark file into the nix-store.
    # As the symlink will point to the users home directory, no other user 
    # should have permission to read the content of this file.
    xdg.configFile."surfraw/bookmarks" = mkIf (cfg.addBookmark.file != null) {
      source = if cfg.addBookmark.toStore 
        then cfg.addBookmark.file 
        else config.lib.file.mkOutOfStoreSymlink cfg.addBookmark.file;
    };

    xdg.configFile."surfraw/conf".text = ''
      # Generated by Home Manager.
      # See http://surfraw.org or the projects README over at
      # https://gitlab.com/surfraw/Surfraw/-/blob/master/README

      ${configText}
    '';
  };
}
