#!/usr/bin/env bash
# The gate for this repository: lint what the skill ships, hold it to its own rules, and
# prove that each of its checks can actually go red. A check that has never failed is a
# decoration, and this skill hands its checker to other repositories.
#
# Nothing here touches the network, so it is safe on pull requests.
# Needs: actionlint, shellcheck, shfmt, zsh — from the flake's dev shell, never from PATH's luck.
#
#   nix develop -c ./check.sh
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# One source of truth for what gets linted. A second copy of this list drifts, and a
# drifted list lies about what was checked.
scripts=(check.sh check-skill.sh check-pins.sh check-changelog.sh vendor-sync.sh)
skill_name=bash-best-practices

fail() {
  echo "check: $1" >&2
  exit 1
}

# With a template, because the BSD mktemp on macOS wants one
work=$(mktemp -d "${TMPDIR:-/tmp}/check.XXXXXX")
trap 'rm -rf "$work"' EXIT

missing=()
for tool in actionlint shellcheck shfmt zsh; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
((${#missing[@]} == 0)) ||
  fail "missing: ${missing[*]} — they are pinned in the flake, so run this as: nix develop -c ./check.sh"

echo "== the scripts parse and lint"
for s in "${scripts[@]}"; do bash -n "$s"; done
shellcheck "${scripts[@]}"
shfmt -d -i 2 -ci "${scripts[@]}"

echo "== the workflows are valid, and their tools come from the lock rather than a registry"
[[ -d .github/workflows ]] || fail ".github/workflows is missing — nothing gates this repository"
actionlint
# The checkers below are vendored from the ci and versioning skills: every copy must still
# be the blob .github/vendor.lock records, so one edited here instead of at its source
# fails by name
./vendor-sync.sh check
# The pin guard proves on every run that it catches each unpinned shape and stays quiet on
# the pinned spellings, then scans the workflows
./check-pins.sh
# And the pins have to be watched: a major tag moves within its major on its own, but
# nothing says when GitHub retires the runtime an old major runs on, except a red run
# with no change in the repository. dependabot's pull request arrives first.
[[ -f .github/dependabot.yml ]] ||
  fail ".github/dependabot.yml is missing — the action pins in the workflows are watched by nobody"
grep -q 'package-ecosystem: github-actions' .github/dependabot.yml ||
  fail ".github/dependabot.yml does not watch the github-actions ecosystem"

echo "== the flake evaluates for every system it claims, not only for this one"
# `nix flake check` reads the system it is run on and says "all checks passed", which is
# how a flake in this family named a platform that could not be evaluated at all. The
# list is read out of the flake rather than repeated here, one eval for all of them, and
# --offline so the gate's promise about the network still holds.
flake_systems=$(nix eval --offline --json '.#devShells' \
  --apply 'ss: builtins.mapAttrs (n: v: v.default.drvPath) ss' 2>"$work/flake.err") ||
  fail "the flake claims a system it cannot be evaluated for: $(sed 's/^ *//' "$work/flake.err" | grep -m 1 -E 'error: .+' || tail -1 "$work/flake.err")"
[[ "$flake_systems" == *x86_64-linux* ]] ||
  fail "the flake does not offer a dev shell on x86_64-linux, which is what CI runs the gate on"

echo "== no paragraph in the docs is hard-wrapped or ends on a full stop"
# GitHub soft-wraps, so a manual break means a one-word edit reflows every line after it,
# and a paragraph ends bare. The rules' home is the create-readme skill, which cannot be
# assumed present in CI, so their machine-decidable part is spelled here — over every doc
# the skill ships, not the readme alone: SKILL.md and the references are what an agent reads
docs=(README.md SKILL.md CHANGELOG.md)
[[ -d references ]] && docs+=(references/*.md)
hard_wrapped() { # hard_wrapped FILE -> the offending line numbers
  awk '
    # the frontmatter is YAML, whose keys sit one per line
    NR == 1 && /^---$/ { front = 1; next }
    front { if (/^---$/) front = 0; next }
    /^```/ { fence = !fence; prev = 0; item = 0; next }
    fence { next }
    # a list item continued on an indented line is a wrapped list item
    item && /^  +[^ ]/ && !/^  +([-*+]|[0-9]+\.) / { print NR; next }
    /^[-*+] / || /^[0-9]+\. / { prev = 0; item = 1; next }
    /^[[:space:]]*$/ || /^[#|>< ]/ || /^!\[/ || /^\[/ { prev = 0; item = 0; next }
    { if (prev) print NR; prev = 1; item = 0 }
  ' "$1"
}
full_stopped() { # full_stopped FILE -> the lines of prose that end on a full stop
  awk '
    NR == 1 && /^---$/ { front = 1; next }
    front { if (/^---$/) front = 0; next }
    /^```/ { fence = !fence; next }
    fence || /^    / || /^[|]/ { next }
    # seen through the markup that can close after it: `.**` and `.)` end on a stop too
    { s = $0; sub(/[*_)`"]+$/, "", s); if (s ~ /[^.]\.$/) print NR }
  ' "$1"
}
for doc in "${docs[@]}"; do
  wrapped=$(hard_wrapped "$doc")
  [[ -z "$wrapped" ]] ||
    fail "$doc hard-wraps a paragraph at line(s): $(tr '\n' ' ' <<<"$wrapped")— one paragraph is one line"
  stopped=$(full_stopped "$doc")
  [[ -z "$stopped" ]] ||
    fail "$doc ends prose on a full stop at line(s): $(tr '\n' ' ' <<<"$stopped")— the last sentence ends bare"
done
# Both able to fail, on the shapes they claim: a wrapped paragraph and a wrapped list item,
# a full stop bare and one behind closing markup
printf 'one line of a paragraph\nand the next line of it\n\n- a list item\n  wrapped onto a second line\n' >"$work/wrapped.md"
[[ "$(hard_wrapped "$work/wrapped.md" | wc -l)" -eq 2 ]] ||
  fail "the hard-wrap check missed a wrapped paragraph or a wrapped list item"
printf 'A sentence.\n\n**A bold one.**\n\n(A parenthesis.)\n' >"$work/stopped.md"
[[ "$(full_stopped "$work/stopped.md" | wc -l)" -eq 3 ]] ||
  fail "the full-stop check missed a full stop, bare or behind markup"

echo "== SKILL.md loads, every reference is reachable, and every link and anchor resolves"
# The one gate every skill repository shares, vendored from the ci skill. It proves each
# of its own checks able to fail on every run, so nothing here has to
./check-skill.sh -n "$skill_name" .

echo "== the changelog obeys the versioning skill's rules"
./check-changelog.sh -n CHANGELOG.md

echo
echo "check: everything holds"
