{ modules, testedAttrPath, tests, pkgs, lib ? pkgs.lib }:

with lib;

let

  evalTest = name: test:
    evalModules {
      modules = let
        initModule = { config, ... }: {
          nmt.name = name;
          nmt.tested = getAttrFromPath testedAttrPath config;
        };
      in [ initModule ./nmt.nix test ] ++ modules;
    };

  evaluatedTests = mapAttrs evalTest tests;

  scriptPath = makeBinPath (with pkgs; [
    coreutils
    ncurses # For tput.
  ]);

  runScript = name: script:
    runShellOnlyCommand name ''
      set -uo pipefail

      export PATH="${scriptPath}"

      . "${./bash-lib/color-echo.sh}"

      ${script}

      exit 0
    '';

  runShellOnlyCommand = name: shellHook:
    pkgs.runCommandLocal name { inherit shellHook; } ''
      echo This derivation is only useful when run through nix-shell.
      exit 1
    '';

  reportResult = { name, result, onSuccess, onError }:
    if result.success then ''
      noteEcho "${name}: OK"
      ${onSuccess}
    '' else ''
      errorEcho "${name}: FAILED"
      cat "${result.report}/output"
      echo "For further reference please introspect ${result.report}"
      ${onError}
    '';

  buildTest = name: test: test.config.nmt.result.build;

  buildAllTests = pkgs.linkFarm "nmt-all-tests" (mapAttrsToList (n: test: {
    name = n;
    # We have to be careful here: we are evaluating all the tests at once, which
    # might require a lot of memory. In order to allow the memory from each evaluation
    # to be garbage-collected, we must not leave any thunks referring to `evalTest n t`
    # alive. Thus,
    # - we can't use the top-level `evaluatedTests` binding (which effectively keeps a
    #   GC root to all of the evaluations);
    # - we have to force the `build` derivation into a string.
    path = "${(evalTest n test).config.nmt.result.build}";
  }) tests);

  runTest = name: test:
    runScript "nmt-run-${name}" (reportResult {
      inherit (test.config.nmt) name result;
      onSuccess = "exit 0";
      onError = "exit 1";
    });

  runAllTests = let
    # Just like in buildAllTests, we need to make sure that each element of the
    # list is strictly evaluated in order to avoid leaving live thunks behind.
    reports = mapAttrsToList (n: test:
      let
        evaluated = (evalTest n test).config.nmt;
        self = {
          inherit (evaluated.result) success;
          report = reportResult {
            inherit (evaluated) name result;
            onSuccess = "";
            onError = "ERR=1";
          };
        };
      in deepSeq self self) tests;
    # Print failed tests last.
    succeeded = partition (t: t.success) reports;
    ordered = succeeded.right ++ succeeded.wrong;
  in runScript "nmt-run-all-tests"
  (concatStringsSep "\n\n" (map (t: t.report) ordered) + ''
    if [[ -v ERR ]]; then
      exit 1
    else
      exit 0
    fi
  '');

in {
  build = mapAttrs buildTest evaluatedTests // { all = buildAllTests; };

  run = mapAttrs runTest evaluatedTests // { all = runAllTests; };

  report = mapAttrs (name: test: test.config.nmt.result.report) evaluatedTests;

  list = runScript "nmt-list-tests" (let
    scripts = concatStringsSep "\n" (map (n: "echo ${n}") (attrNames tests));
  in ''
    echo all
    ${scripts}
  '');
}
