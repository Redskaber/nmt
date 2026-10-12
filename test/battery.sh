# -*- mode: sh; sh-shell: bash -*-

# nmt self-test battery — the test framework tests its own assertion
# library. Run standalone (`bash test/battery.sh`) or via Nix
# (`nix build -f test/`), see test/default.nix.
#
# The battery has three classes of cases:
#
#   1. positive — each assertion passes on a fitting fixture;
#   2. negative — each assertion FAILS where it must (a test framework
#      that cannot fail is not a test framework);
#   3. adversarial needles — patterns that LOOK like grep options
#      ("--smart-case", "-x", "--"). These are the exact regression
#      class of the `--` end-of-options guards: before the guards a
#      leading dash made grep read the needle as a flag (an error, or
#      worse, a silent wrong match); the guards must also NOT turn
#      into a blanket pass — an absent option-looking needle must
#      still fail.
#
# Exit code 0 = every case behaved; 1 = at least one did not, with a
# per-case report on stdout.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The assertions library: env override first (the Nix entry in
# test/default.nix passes the store-copied file — path interpolation
# there lands battery.sh in the store FLAT, with no ../bash-lib next to
# it), else the checkout-relative location.
NMT_ASSERTIONS_SRC="${NMT_ASSERTIONS_SRC:-$SCRIPT_DIR/../bash-lib/assertions.sh}"
if [[ ! -f $NMT_ASSERTIONS_SRC ]]; then
    echo "FATAL: assertions.sh not found at: $NMT_ASSERTIONS_SRC" >&2
    exit 2
fi
# shellcheck disable=SC1090
source "$NMT_ASSERTIONS_SRC"
# A failed source must be loud, not a silent no-op: every assertion
# case would otherwise report "command not found" as its own failure.
if ! declare -F assertFileExists >/dev/null; then
    echo "FATAL: sourcing $NMT_ASSERTIONS_SRC did not define the assertion API" >&2
    exit 2
fi

# Standalone mode: give the assertions a $TESTED tree and $out dir.
if [[ -z ${TESTED:-} ]]; then
    TESTED="$(mktemp -d)"
fi
if [[ -z ${out:-} ]]; then
    out="$(mktemp -d)"
fi
# NIX_STORE is provided by the Nix build environment; standalone mode
# falls back to the canonical path so normalizeStorePaths works equally
# in both modes.
if [[ -z ${NIX_STORE:-} ]]; then
    export NIX_STORE="/nix/store"
fi
export TESTED

PASS=0
FAIL=0
FAILED_CASES=""

# must_pass <name> <function> [args...]
# The assertion must succeed; its error output is shown if it does not.
must_pass() {
    local name="$1"
    shift
    local output
    if output="$("$@" 2>&1)"; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected success)"
        [[ -n $output ]] && echo "      assertion said: $output"
        FAIL=$((FAIL + 1))
        FAILED_CASES="$FAILED_CASES
  - $name"
    fi
}

# must_fail <name> <function> [args...]
# The assertion must fail — testing the tester. The parens are load-
# bearing: assertions "fail" via exit 1, which must only end the
# subshell, not the battery.
must_fail() {
    local name="$1"
    shift
    if ( "$@" ) >/dev/null 2>&1; then
        echo "FAIL: $name (expected failure, assertion passed instead)"
        FAIL=$((FAIL + 1))
        FAILED_CASES="$FAILED_CASES
  - $name"
    else
        echo "PASS: $name (failed as expected)"
        PASS=$((PASS + 1))
    fi
}

note_case() {
    local name="$1"
    local ok="$2"
    if [[ $ok == 1 ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
        FAILED_CASES="$FAILED_CASES
  - $name"
    fi
}

# ── fixtures ───────────────────────────────────────────────────────────

printf 'plain text line\nsecond line\n' >"$TESTED/plain.txt"
printf -- '--smart-case\n-x\n--\nmulti word needle here\noption: --verbose\n' >"$TESTED/flags.txt"
printf 'plain text line\nsecond line\n' >"$TESTED/plain-expected.txt"
printf '#!/bin/sh\necho ok\n' >"$TESTED/exec.sh"
chmod +x "$TESTED/exec.sh"
mkdir -p "$TESTED/dir_empty" "$TESTED/dir_full"
touch "$TESTED/dir_full/item"
ln -s target-file "$TESTED/link"
ln -s missing-target "$TESTED/dangling-link"
# A file carrying real-looking store references, for normalizeStorePaths.
printf 'export PATH=/nix/store/00000000000000000000000000000000-nothing/bin\ntool = "/nix/store/1abc2def3abc4def5abc6def7abc8def-coreutils-9.5/bin/tool"\n' >"$TESTED/store-refs.txt"
printf 'SELFTEST_SOURCED=1\n' >"$TESTED/sourced-snippet.sh"

# ── 1. positive paths ─────────────────────────────────────────────────

must_pass "assertFileExists: present file" \
    assertFileExists plain.txt

must_pass "assertPathNotExists: absent path" \
    assertPathNotExists missing.txt

must_pass "assertFileContains: plain needle" \
    assertFileContains plain.txt "plain text line"

must_pass "assertFileContains: needle with spaces" \
    assertFileContains flags.txt "multi word needle here"

must_pass "assertFileRegex: anchored plain ERE" \
    assertFileRegex plain.txt "^second line$"

must_pass "assertFileNotRegex: absent pattern" \
    assertFileNotRegex plain.txt "^absent-pattern$"

must_pass "assertFileIsExecutable: exec bit set" \
    assertFileIsExecutable exec.sh

must_pass "assertFileIsNotExecutable: no exec bit" \
    assertFileIsNotExecutable plain.txt

must_pass "assertLinkExists: symlink present" \
    assertLinkExists link

must_pass "assertLinkPointsTo: correct target" \
    assertLinkPointsTo link target-file

must_pass "assertLinkPointsTo: dangling link target passthrough" \
    assertLinkPointsTo dangling-link missing-target

must_pass "assertDirectoryExists: directory present" \
    assertDirectoryExists dir_empty

must_pass "assertDirectoryEmpty: empty directory" \
    assertDirectoryEmpty dir_empty

must_pass "assertDirectoryNotEmpty: populated directory" \
    assertDirectoryNotEmpty dir_full

must_pass "assertFileContent: identical content" \
    assertFileContent plain.txt "$TESTED/plain-expected.txt"

# ── 2. negative paths — the framework must fail where it must ──────────

must_fail "assertFileExists: missing file fails" \
    assertFileExists missing.txt

must_fail "assertPathNotExists: present path fails" \
    assertPathNotExists plain.txt

must_fail "assertFileContains: absent needle fails" \
    assertFileContains plain.txt "absent needle"

must_fail "assertFileRegex: non-matching ERE fails" \
    assertFileRegex plain.txt "^absent$"

must_fail "assertFileNotRegex: matching ERE fails" \
    assertFileNotRegex plain.txt "^plain text"

must_fail "assertFileIsExecutable: non-executable fails" \
    assertFileIsExecutable plain.txt

must_fail "assertFileIsNotExecutable: executable fails" \
    assertFileIsNotExecutable exec.sh

must_fail "assertLinkExists: regular file is not a link" \
    assertLinkExists plain.txt

must_fail "assertLinkPointsTo: wrong target fails" \
    assertLinkPointsTo link wrong-target

must_fail "assertDirectoryEmpty: populated directory fails" \
    assertDirectoryEmpty dir_full

must_fail "assertDirectoryNotEmpty: empty directory fails" \
    assertDirectoryNotEmpty dir_empty

must_fail "assertFileContent: differing content fails" \
    assertFileContent flags.txt "$TESTED/plain-expected.txt"

# ── 3. adversarial needles — the `--` guard regression battery ─────────
#
# The exact class fixed by "pass -- before grep patterns": needles that
# look like grep options. Before the guards these errored out (or
# silently matched the wrong thing); after the guards they are ordinary
# needles. And the mirror case: an ABSENT option-looking needle must
# still fail — a guard must not become a blanket pass.

must_pass "assertFileContains: option-looking needle --smart-case" \
    assertFileContains flags.txt "--smart-case"

must_pass "assertFileContains: single-dash needle -x" \
    assertFileContains flags.txt "-x"

must_pass "assertFileContains: bare double-dash needle --" \
    assertFileContains flags.txt "--"

must_pass "assertFileContains: option value in longer needle" \
    assertFileContains flags.txt "option: --verbose"

must_pass "assertFileRegex: anchored option-looking ERE ^--smart-case" \
    assertFileRegex flags.txt "^--smart-case$"

must_pass "assertFileNotRegex: absent option-looking ERE" \
    assertFileNotRegex flags.txt "^--missing-option$"

must_fail "assertFileContains: absent option-looking needle fails" \
    assertFileContains flags.txt "--not-in-file"

must_fail "assertFileContains: option-looking needle on wrong file fails" \
    assertFileContains plain.txt "--smart-case"

must_fail "assertFileNotRegex: present option-looking ERE fails" \
    assertFileNotRegex flags.txt "^--smart-case"

# ── 4. helpers — normalizeStorePaths, sourceFile ────────────────────────
# These need the caller's shell (output capture / current-shell state),
# so they get bespoke checks instead of the subshell wrappers.

normalized="$(normalizeStorePaths store-refs.txt)"
normalized_content="$(cat "$normalized")"
if [[ $normalized_content == *"export PATH=/nix/store/00000000000000000000000000000000-nothing/bin"* ]]; then
    note_case "normalizeStorePaths: already-normalized hash stays normalized" 1
else
    note_case "normalizeStorePaths: already-normalized hash stays normalized" 0
fi
# The rewrite also drops the version segment (the sed's group 2 is not
# part of the replacement) — normalization must collapse version drift
# too, so version-less names are the EXPECTED form here.
if [[ $normalized_content == *"/nix/store/00000000000000000000000000000000-coreutils/bin/tool"* ]]; then
    note_case "normalizeStorePaths: real-looking hash is rewritten to the zero form" 1
else
    note_case "normalizeStorePaths: real-looking hash is rewritten to the zero form" 0
fi

# sourceFile: runs in THIS shell (its whole point), so run it directly
# and observe the sourced state. A missing fixture would abort here —
# the fixture above is local, so that is itself a failure we want loud.
sourceFile sourced-snippet.sh
if [[ ${SELFTEST_SOURCED:-} == 1 ]]; then
    note_case "sourceFile: sourced variable visible in the caller" 1
else
    note_case "sourceFile: sourced variable visible in the caller" 0
fi

# ── verdict ────────────────────────────────────────────────────────────

echo
echo "nmt self-test battery: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "failed cases:$FAILED_CASES"
    exit 1
fi
exit 0
