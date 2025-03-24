# Collects the various test modules in tests/test-sources/ and groups them into a number of test derivations
{
  callTest,
  helpers,
  lib ? pkgs.lib,
  linkFarm,
  pkgs,
  self,
  system,
}:
let
  fetchTests = callTest ./fetch-tests.nix { };

  # Use a single common instance of nixpkgs, with allowUnfree
  # Having a single shared instance should speed up tests a little
  pkgsForTest = import self.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  moduleToTest =
    file: name: module:
    let
      configuration = lib.nixvim.modules.evalNixvim {
        modules = [
          {
            test.name = lib.mkDefault name;
            _module.args.pkgs = lib.mkForce pkgsForTest;
          }
          {
            _file = file;
            imports = lib.toList module;
          }
        ];
      };
    in
    configuration.config.build.test;

  # List of files containing configurations
  testFiles = fetchTests ./test-sources;

  exampleFiles = {
    name = "examples";
    file = ../example.nix;
    cases =
      let
        config = import ../example.nix { inherit pkgs; };
      in
      {
        main = builtins.removeAttrs config.programs.nixvim [
          # This is not available to standalone modules, only HM & NixOS Modules
          "enable"
          # This is purely an example, it does not reflect a real usage
          "extraConfigLua"
          "extraConfigVim"
        ];
      };
  };
in
# We attempt to build & execute all configurations
lib.pipe (testFiles ++ [ exampleFiles ]) [
  (builtins.map (
    {
      name,
      file,
      cases,
    }:
    {
      inherit name;
      path = linkFarm name (builtins.mapAttrs (moduleToTest file) cases);
    }
  ))
  (helpers.groupListBySize 10)
  (lib.imap1 (
    i: group: rec {
      name = "test-${toString i}";
      value = linkFarm name group;
    }
  ))
  builtins.listToAttrs
]
