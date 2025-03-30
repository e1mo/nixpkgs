testModuleArgs@{
  config,
  options,
  lib,
  hostPkgs,
  nodes,
  moduleType,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    either
    str
    functionTo
    pathInStore
    nullOr
    ;

  stringScriptDefined = options.testScript.isDefined && config.testScript != null;
  fileScriptDefined = options.testScriptFile.isDefined && config.testScriptFile != null;
  xor = a: b: (a || b) && (a -> !b);
in
{
  options = {
    testScript = mkOption {
      type = nullOr (either str (functionTo str));
      default = null;
      description = ''
        A series of python declarations and statements that you write to perform
        the test.
        Mutually exclusive with {option}`testScriptFile`.
      '';
    };
    # We could also make testScript accept either a path or (function mapping to) a string. This would solve the xor and check foo.
    testScriptFile = mkOption {
      type = nullOr pathInStore;
      default = null;
      description = ''
        A file containing the same python Test-Script you'd usually pass to
        `testScript`.
        Mutually exclusive with {option}`testScript`.
      '';
    };
    _testScriptFile = mkOption {
      type = pathInStore;
      internal = true;
      visible = false;
      readOnly = true;
    };
    testScriptString = mkOption {
      type = str;
      readOnly = true;
      internal = true;
    };

    includeTestScriptReferences = mkOption {
      type = types.bool;
      default = true;
      internal = true;
    };
    withoutTestScriptReferences = mkOption {
      type = moduleType;
      description = ''
        A parallel universe where the testScript is invalid and has no references.
      '';
      internal = true;
      visible = false;
    };
  };
  config = {
    withoutTestScriptReferences.includeTestScriptReferences = false;
    withoutTestScriptReferences.testScript = lib.mkForce "testscript omitted";

    testScriptString =
      if lib.isFunction config.testScript then
        config.testScript {
          nodes = lib.mapAttrs (
            k: v:
            if v.virtualisation.useNixStoreImage then
              # prevent infinite recursion when testScript would
              # reference v's toplevel
              config.withoutTestScriptReferences.nodesCompat.${k}
            else
              # reuse memoized config
              v
          ) config.nodesCompat;
        }
      else
        config.testScript;

    _testScriptFile =
      if (xor stringScriptDefined fileScriptDefined) then
        (
          if stringScriptDefined then
            hostPkgs.writeText "test-script.py" config.testScriptString
          else
            config.testScriptFile
        )
      else
        throw "Either one of `testScript' or `testScriptFile' must be set, but not both.";

    passthru = {
      inherit (config) _testScriptFile;
    };

    defaults =
      { config, name, ... }:
      {
        # Make sure all derivations referenced by the test
        # script are available on the nodes. When the store is
        # accessed through 9p, this isn't important, since
        # everything in the store is available to the guest,
        # but when building a root image it is, as all paths
        # that should be available to the guest has to be
        # copied to the image.
        # A testScript may evaluate nodes, which has caused
        # infinite recursions. The demand cycle involves:
        #   testScript -->
        #   nodes -->
        #   toplevel -->
        #   additionalPaths -->
        #   hasContext testScript' -->
        #   testScript (ad infinitum)
        # If we don't need to build an image, we can break this
        # cycle by short-circuiting when useNixStoreImage is false.
        virtualisation.additionalPaths =
          # Since writeText propagates the string context we don't
          # have to handle testScriptString and testScriptFile separately.
          lib.optional (
            config.virtualisation.useNixStoreImage && testModuleArgs.config.includeTestScriptReferences
          ) testModuleArgs.config._testScriptFile;
      };
  };
}
