#!/usr/bin/env bash
# A check that has never failed is a decoration, and this skill hands its checker to other
# repositories
set -euo pipefail

usage() {
  cat <<'EOF'
check.sh — the gate for this repository: lint what the skill ships, hold it to its own
rules, and prove that each of its checks can actually go red

  check.sh [lint|behaviour|all]

Two halves, because they need different things. lint reads what the skill ships —
scripts, workflows, docs, templates — and needs actionlint, shellcheck, shfmt and zsh
from the flake's dev shell, never from whatever the runner has. behaviour runs
check-sh.sh against scripts and planted copies and needs only bash, so it can be run
under the bash 3.2 that macOS ships, which is what the checker claims to run on. all,
the default, is both

  nix develop -c ./check.sh
  /bin/bash ./check.sh behaviour        # on a macOS runner, CHECK_BASH32=1

Environment: CHECK_BASH32=1 says this bash is the 3.2 under proof, and adds the probes
only that bash can fail
Nothing here touches the network, so it is safe on pull requests
Exit 0 when everything holds, 1 on a failure or an unknown mode
EOF
}

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# One source of truth for what gets linted. A second copy of this list drifts, and a
# drifted list lies about what was checked.
scripts=(check.sh check-sh.sh check-skill.sh check-pins.sh check-changelog.sh vendor-sync.sh templates/script.sh)
bash_completions=(templates/completions/script.sh.bash)
zsh_completions=(templates/completions/_script.sh)
skill_name=bash-best-practices

fail() {
  echo "check: $1" >&2
  exit 1
}

# Every check-sh.sh below runs under the bash running this gate, not under whatever bash
# the shebang finds: on a macOS runner the gate is started as `/bin/bash ./check.sh` to
# prove the checker on the 3.2 that macOS ships, while `env bash` would find Homebrew's 5.
checker() { "$BASH" "$HERE/check-sh.sh" "$@"; }

# With a template, so a crashed run's leftovers say whose they are
work=$(mktemp -d "${TMPDIR:-/tmp}/check.XXXXXX")
trap 'rm -rf "$work"' EXIT

mode="${1:-all}"
case "$mode" in
  lint | behaviour | all) ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  *) fail "no such mode: '$mode' — lint, behaviour or all" ;;
esac

tools=()
[[ "$mode" == behaviour ]] || tools+=(actionlint shellcheck shfmt zsh)
missing=()
for tool in "${tools[@]+"${tools[@]}"}"; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
((${#missing[@]} == 0)) ||
  fail "missing: ${missing[*]} — they are pinned in the flake, so run this as: nix develop -c ./check.sh"

check_lint() {
  echo "== the scripts parse and lint"
  # Only this file: check-sh.sh parses every script it is given, names it, and on the
  # macOS runner does it under the 3.2 the claim is about — and it is run on each of the
  # others below. The gate itself is the one script it never sees
  bash -n check.sh
  shellcheck "${scripts[@]}" "${bash_completions[@]}"
  shfmt -d -i 2 -ci "${scripts[@]}" "${bash_completions[@]}"
  # zsh is not shellcheck's language; a parse is what can be checked
  for z in "${zsh_completions[@]}"; do zsh -n "$z"; done

  echo "== the workflows are valid, and their tools come from the lock rather than a registry"
  [[ -d .github/workflows ]] || fail ".github/workflows is missing — nothing gates this repository"
  actionlint
  # The template workflow is a workflow too, and named explicitly actionlint needs no
  # project around it
  actionlint templates/github/workflows/macos.yml
  # The checkers below are vendored from the ci and versioning skills: every copy must
  # still be the blob .github/vendor.lock records, so one edited here instead of at its
  # source fails by name
  ./vendor-sync.sh check
  # The pin guard proves on every run that it catches each unpinned shape and stays quiet
  # on the pinned spellings, then scans the workflows and the template
  ./check-pins.sh .github/workflows templates/github/workflows
  # And the pins have to be watched: a major tag moves within its major on its own, but
  # nothing says when GitHub retires the runtime an old major runs on, except a red run
  # with no change in the repository. dependabot's pull request arrives first.
  [[ -f .github/dependabot.yml ]] ||
    fail ".github/dependabot.yml is missing — the action pins in the workflows are watched by nobody"
  grep -q 'package-ecosystem: github-actions' .github/dependabot.yml ||
    fail ".github/dependabot.yml does not watch the github-actions ecosystem"

  echo "== the workflow this repository runs on macOS is the template it hands out"
  # The template is what other repositories copy, so the copy this repository runs must
  # be the template itself, or the proof here says nothing about what travels
  cmp -s .github/workflows/macos.yml templates/github/workflows/macos.yml ||
    fail ".github/workflows/macos.yml differs from templates/github/workflows/macos.yml — one of them drifted"

  echo "== the templates are what the checker prints, and the checker holds them"
  # The skeleton a new script starts from and the script the checker plants its defects
  # into are one text: check-sh.sh --template prints it, and templates/ must be that
  # output byte for byte
  for pair in "script:templates/script.sh" "bash:templates/completions/script.sh.bash" "zsh:templates/completions/_script.sh"; do
    kind="${pair%%:*}"
    file="${pair#*:}"
    checker --template "$kind" >"$work/template.$kind"
    cmp -s "$work/template.$kind" "$file" ||
      fail "$file differs from check-sh.sh --template $kind — the template is generated, so regenerate it rather than editing it"
  done

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
  # GitHub soft-wraps, so a manual break means a one-word edit reflows every line after
  # it, and a paragraph ends bare. The rules' home is
  # https://github.com/rokokol/create-readme-skill, which cannot be assumed present in CI,
  # so their machine-decidable part is spelled here — over every
  # doc the skill ships, not the readme alone: SKILL.md and the references are what an
  # agent reads
  docs=(README.md SKILL.md CHANGELOG.md references/*.md)
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
  # Both able to fail, on the shapes they claim: a wrapped paragraph and a wrapped list
  # item, a full stop bare and one behind closing markup
  printf 'one line of a paragraph\nand the next line of it\n\n- a list item\n  wrapped onto a second line\n' >"$work/wrapped.md"
  [[ "$(hard_wrapped "$work/wrapped.md" | wc -l)" -eq 2 ]] ||
    fail "the hard-wrap check missed a wrapped paragraph or a wrapped list item"
  printf 'A sentence.\n\n**A bold one.**\n\n(A parenthesis.)\n' >"$work/stopped.md"
  [[ "$(full_stopped "$work/stopped.md" | wc -l)" -eq 3 ]] ||
    fail "the full-stop check missed a full stop, bare or behind markup"

  echo "== SKILL.md loads, every reference is reachable, and every link and anchor resolves"
  # The one gate every skill repository shares, vendored from
  # https://github.com/rokokol/ci-skill. It proves each of its own checks able to fail on
  # every run, so nothing here has to
  ./check-skill.sh -n "$skill_name" .

  echo "== the changelog obeys the versioning skill's rules"
  # Pinned: without -t a changelog moved wholesale to another template stays green, which is
  # the versioning skill's PITFALLS.md
  ./check-changelog.sh -n -t '## {date}' CHANGELOG.md
}

check_behaviour() {
  echo "== the checker holds this skill's own scripts to the form, itself first"
  # check-sh.sh proves every one of its checks able to fail on each run, on a canonical
  # script with one defect planted, so running it is both the gate on these scripts and
  # the falsification of the checker
  # Its own documents included: every `check-sh.sh …` span in SKILL.md and the readme must
  # spell flags it parses
  checker -m SKILL.md -d README.md check-sh.sh
  checker -e SCRIPT_ -c templates/completions/script.sh.bash templates/completions/_script.sh templates/script.sh
  # vendor-sync.sh was red on the checker's first run, for a real reason: its dispatcher
  # spelled the help arm `-h | --help)` without `help`. The fix went to its source in
  # https://github.com/rokokol/ci-skill and the cascade brought it here, which is how a copy
  # is meant to change
  for s in check-skill.sh check-pins.sh check-changelog.sh vendor-sync.sh; do checker "$s"; done

  echo "== every construct fires under a claim below its floor, is silent at it, and silent with no claim"
  # The constructs live in a fixture rather than inline here, because spelling them in
  # this file would make the proxy match its own proof, and check.sh is itself a script
  # this gate would then have to excuse
  # Each construct is planted inside a function nothing calls, so the copy's --help still
  # runs under a bash that parses it; under a real 3.2 some of them do not parse at all,
  # which is why the checker greps before it asks for the help
  planted_count=0
  while IFS=$'\t' read -r need planted; do
    [[ -z "$planted" || "$need" == \#* ]] && continue
    planted_count=$((planted_count + 1))
    checker --template >"$work/claimed.sh"
    printf 'planted_never_called() {\n  %s\n}\n' "$planted" >>"$work/claimed.sh"
    out=$(checker -n script.sh "$work/claimed.sh" 2>&1) &&
      fail "the proxy does not catch, under a 3.2 claim: $planted"
    [[ "$out" == *"claims bash 3.2 but"*"$planted"* ]] ||
      fail "the proxy rejected '$planted' for the wrong reason: $out"
    # And the other half of the same row: a script that declares the floor this construct
    # needs — or drops the POSIX userland claim, for a row that is about the userland — is
    # entitled to it, and the proxy must stay quiet. Without this the checker could be one
    # that fires on everything, which the half above alone cannot tell apart
    if [[ "$need" == bsd ]]; then
      entitled='s/^\(# .*\)Needs bash 3\.2 and POSIX tools only/\1Needs bash 3.2/'
    else
      entitled=$(printf 's/^\\(# .*\\)Needs bash 3\\.2/\\1Needs bash %d.%d/' $((need / 100)) $((need % 100)))
    fi
    checker --template | sed "$entitled" >"$work/entitled.sh"
    printf 'planted_never_called() {\n  %s\n}\n' "$planted" >>"$work/entitled.sh"
    # A copy this bash cannot parse says nothing about the proxy. The catching half above
    # runs anywhere, because the checker greps before it asks for the help; this half needs
    # the copy's own --help to run, and under the 3.2 macOS ships a 4.x construct is a
    # syntax error rather than a finding — which the macOS job read as the proxy firing
    if "$BASH" -n "$work/entitled.sh" 2>/dev/null; then
      out=$(checker -n script.sh "$work/entitled.sh" 2>&1) ||
        fail "the proxy fired on '$planted' in a script entitled to it ($need): $out"
    fi
  done <tests/fixtures/bash4-constructs.sh
  ((planted_count >= 20)) || fail "only $planted_count constructs were read from the fixture — the extractor is broken"
  # And the whole fixture at once in a script that declares nothing: a header that makes no
  # claim has promised nothing about where it runs, so not one of these is a finding there.
  # Under a real 3.2 such a script cannot even be parsed, so that control has nothing to say
  if ((BASH_VERSINFO[0] >= 4)); then
    {
      # The claim line goes entirely, rather than being rewritten to another version, which
      # would only move the floor and leave everything above it firing
      checker --template | sed '/Needs bash 3\.2/d'
      printf 'planted_never_called() {\n'
      grep -vE '^#|^$' tests/fixtures/bash4-constructs.sh | cut -f2-
      printf '}\n'
    } >"$work/unclaimed.sh"
    checker -n script.sh "$work/unclaimed.sh" >/dev/null 2>&1 ||
      fail "the proxy fired on a script that declares no floor and no userland — a claim is what turns it on"
  else
    echo "   the no-claim control skipped: this bash is $BASH_VERSION and cannot parse the fixture"
  fi

  echo "== the checker refuses rather than guessing"
  # Exit 2 and a message, rather than 1 and a finding: a missing file or a script with
  # nothing to hold to its help is not a drift, and a gate that conflated the two would
  # report a typo as a rule violation — or worse, pass on nothing
  refuses() { # refuses WHAT EXPECTED-FRAGMENT [ARGS...]
    local what="$1" want="$2" status=0 out
    shift 2
    out=$(checker "$@" 2>&1) || status=$?
    ((status == 2)) || fail "the checker did not refuse $what (got $status): $out"
    [[ "$out" == *"$want"* ]] || fail "the checker refused $what for the wrong reason: $out"
  }
  refuses "no script at all" "check-sh.sh [-n NAME]"
  refuses "a script it cannot read" "cannot read" "$work/not-a-file.sh"
  refuses "two scripts at once" "one script at a time" templates/script.sh templates/script.sh
  refuses "-n with no name" "-n needs a name" templates/script.sh -n
  refuses "-e with no prefix" "-e needs a prefix" templates/script.sh -e
  refuses "-d with no document" "-d needs a document" templates/script.sh -d
  refuses "-m with no document" "-m needs a document" templates/script.sh -m
  refuses "-c with one file" "-c needs two files" templates/script.sh -c templates/completions/script.sh.bash
  refuses "a document it cannot read" "cannot read" -d "$work/not-a-doc.md" templates/script.sh
  refuses "a script with nothing to check" "nothing to check" tests/fixtures/nothing-to-check.sh
  refuses "a script whose --help fails" "--help exited 1" tests/fixtures/help-fails.sh
  refuses "an unknown flag" "check-sh.sh [-n NAME]" --bogus templates/script.sh
  refuses "an unknown template" "no such template" --template nope

  echo "== the checker's own self-test notices when one of its checks is taken away"
  # check-sh.sh proves its checks on a planted copy every run. This is the proof of that
  # proof: a copy of the checker with one finding neutered must fail its own self-test,
  # and for that check's reason. Otherwise the self-test could be passing on nothing
  neutered() { # neutered FRAGMENT WHAT -> a copy whose finding holding FRAGMENT is silenced must go red for WHAT
    local fragment="$1" what="$2" out
    FRAG="$fragment" awk 'index($0, ENVIRON["FRAG"]) { sub(/finding "/, ": \"") } { print }' check-sh.sh >"$work/neutered.sh"
    grep -qF -- "$fragment" "$work/neutered.sh" || fail "no line of check-sh.sh holds '$fragment' — the neutering matched nothing"
    if out=$("$BASH" "$work/neutered.sh" templates/script.sh 2>&1); then
      fail "check-sh.sh with '$fragment' silenced passed its own self-test — the self-test does not prove that check"
    fi
    [[ "$out" == *"a copy with $what"*" passed"* ]] ||
      fail "check-sh.sh with '$fragment' silenced failed for a reason other than its own: $out"
  }
  neutered "dispatches '\$s' but its help never mentions" "a subcommand missing from the help"
  neutered "accepts \$flag but its help never mentions it" "a flag missing from the help"
  neutered "exits \$n but its help never lists" "an exit code missing from the help"
  neutered "never names \$name \$s" "a document that lost a subcommand"
  neutered "is offered by a completion but not parsed" "a completion offering a flag that is not parsed"
  neutered "prints other text through a pipe than from the file" "a usage() printing its help back with sed"
  neutered "belongs to the help alone: \$row" "a usage line in the header comment"
  # Two plants lean on the proxy — a 3.2 claim in the canonical script and in a plain one —
  # and whichever the self-test reaches first is the one that has to notice
  neutered "claims \$claimed but" "a bash 4 construct"
  # And the count of planted defects the summary reports is the count the self-test runs:
  # a lost row would lower it while everything stayed green
  summary=$(checker templates/script.sh 2>&1 | tail -n 1)
  [[ "$summary" =~ \ ([0-9]+)\ planted\ defects\ caught$ ]] || fail "check-sh.sh's summary does not report its planted defects: $summary"
  ((BASH_REMATCH[1] >= 20)) || fail "check-sh.sh reports ${BASH_REMATCH[1]} planted defects, fewer than the 20 it is written to plant"

  # check-sh.sh claims bash 3.2 and travels to repositories that run CI on macOS. A grep
  # for newer syntax is a proxy; the mechanism is the behaviour half under the real 3.2,
  # on a macOS runner, with two constructs planted that only a 3.2 rejects. Under a newer
  # bash they are no defect at all, so this block runs only where CHECK_BASH32 says which
  # bash this is, and first checks that claim.
  if [[ -n "${CHECK_BASH32:-}" ]]; then
    echo "== this bash is the 3.2 the proof is about"
    ((BASH_VERSINFO[0] == 3)) ||
      fail "CHECK_BASH32 is set, but this is bash $BASH_VERSION — on macOS, run: /bin/bash ./check.sh behaviour"
    ! "$BASH" -c 'declare -A m' >/dev/null 2>&1 || fail "CHECK_BASH32 is set, but this bash accepts declare -A"
    awk '{ print } /^set -euo pipefail$/ && !done { print "declare -A check_sh_probe || exit 70"; done = 1 }' check-sh.sh >"$work/probe.sh"
    status=0
    "$BASH" "$work/probe.sh" templates/script.sh >/dev/null 2>&1 || status=$?
    ((status == 70)) || fail "a checker that declares an associative array ran under this bash (got $status) — this is not a 3.2"
    # mapfile does not exist here, so a checker reading its flags with it dies on the spot
    # under set -e — the class of regression only this bash catches, since a newer one
    # runs the same line without a word
    sed 's/^  while IFS= read -r line; do$/  mapfile -t flags < <(cat); while false; do/' check-sh.sh >"$work/mapfile.sh"
    grep -q 'mapfile -t flags' "$work/mapfile.sh" || fail "the mapfile plant did not land in check-sh.sh"
    out=$("$BASH" "$work/mapfile.sh" templates/script.sh 2>&1) && fail "a checker reading its flags with mapfile passed under this bash"
    [[ "$out" == *"mapfile: command not found"* ]] || fail "the mapfile plant failed for a reason other than mapfile being absent: $out"
  fi
}

case "$mode" in
  lint) check_lint ;;
  behaviour) check_behaviour ;;
  all)
    check_lint
    check_behaviour
    ;;
esac

echo
echo "check: everything holds"
