# NMT

This is a basic test framework for projects using the Nixpkgs module
system. It is inspired by the [nix-darwin test framework][nix-darwin].

[nix-darwin]: https://github.com/LnL7/nix-darwin

## This fork's delta

This is a GitHub mirror of [~rycee/nmt][sourcehut] (sourcehut returns
HTTP 403 to Nix fetchers due to bot protection, which makes it
unusable as a flake input) carrying two deltas:

1. `fix(assertions): pass -- before grep patterns` — the three grep
   assertions (`assertFileContains` / `assertFileRegex` /
   `assertFileNotRegex`) pass `--` before the needle, so a needle that
   looks like a grep option (`"--smart-case"`, `"-x"`, …) is matched as
   text instead of being parsed as a flag (an error at best, a silent
   wrong match at worst). Zero behaviour change for ordinary needles.
   Upstream filing: sourcehut mail channel
   `~rycee/nmt@lists.sr.ht` — paste-ready cover letter and patch ship
   with the consumer repo's feedback pack
   (`docs/feedback/nmt-assertions-option-guard.md`).

2. `test/` — the self-test battery: the test framework tests its own
   assertion library. Three case classes: positive paths (every
   assertion passes on a fitting fixture), negative paths (every
   assertion must fail where it must — a test framework that cannot
   fail is not a test framework), and the adversarial-needle battery
   (the `--` guard regression class, including the mirror case: an
   absent option-looking needle must still fail).

   ```console
   $ bash test/battery.sh        # standalone
   $ nix build -f test/          # via Nix (report in ./result)
   ```

[sourcehut]: https://git.sr.ht/~rycee/nmt

