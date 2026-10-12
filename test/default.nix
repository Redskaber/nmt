# nmt self-test harness — Nix entry for the battery in battery.sh.
#
# The test framework tests its own assertion library:
#
#   nix build -f test/              (or: nix build --file test)
#   result/                         → the battery's per-case report
#
# Standalone (no Nix): bash test/battery.sh
#
# The battery covers, per battery.sh's banner:
#   1. positive paths of every assertion;
#   2. negative paths — every assertion must fail where it must;
#   3. adversarial needles — the `--` end-of-options guard regression
#      class ("--smart-case" & co; an absent option-looking needle must
#      still fail — a guard must not become a blanket pass).
#
# pkgs defaults to the ambient <nixpkgs> channel (standard library
# idiom — the same shape nmt's own default.nix assumes with its
# `lib ? pkgs.lib`). Callers with a specific nixpkgs pass it explicitly:
#
#   nix build --expr 'import ./test { pkgs = import <nixpkgs> { }; }'
{ pkgs ? import <nixpkgs> { } }:

pkgs.runCommand "nmt-selftests"
{
  # NMT_ASSERTIONS_SRC: battery.sh lands in the store FLAT (path
  # interpolation copies the file alone), so its ../bash-lib relative
  # source cannot resolve — the env passes the store-copied library
  # explicitly. battery.sh hard-verifies the source (a failed source
  # is a loud FATAL, not 24 "command not found" case failures).
}
  ''
    set -o pipefail
    mkdir -p "$out"
    export NMT_ASSERTIONS_SRC=${../bash-lib/assertions.sh}
    bash ${./battery.sh} | tee "$out/report.txt"
  ''
