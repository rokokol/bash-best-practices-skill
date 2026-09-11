---
name: bash-best-practices
description: "What it is — a standard for the author's sh and bash utilities: one script shape, help as the single source of truth for a CLI, portability to the bash 3.2 and BSD userland macOS ships, measured pitfalls, the traps of an agent's zsh harness, tab completions kept honest by machine, shellcheck and shfmt doctrine, and check-sh.sh, one travelling checker that holds a script's help, docs and completions to its dispatcher. Use when writing, reviewing or refactoring any shell script or CLI wrapper, adding a subcommand, a flag or a completion, deciding which bash a script needs, making a script run on macOS, running ad-hoc shell commands from the Bash tool, or reading a shellcheck or shfmt finding. Triggers: bash, sh, shell script, shebang, set -euo pipefail, usage, --help, subcommand, completion, compdef, shellcheck, shfmt, macOS, BSD, bash 3.2, readlink -f, mktemp, mapfile, zsh, pipefail, скрипт, баш, шелл, напиши скрипт, справка, подкоманда, автодополнение, совместимость с macOS, шеллчек."
license: MIT
---

# bash-best-practices

A shell script is read by three things: a person, its own `--help`, and a completion. The code is the only one of them that is executed, so the code is the only truth, and everything else — the help, a table in a readme, the words a completion offers — is held to it by a machine rather than by memory. Two accounts of one thing disagree within a month; a list nobody checks is a list that has already drifted

The second truth is the machine the script runs on. These utilities travel to macOS, where `/bin/bash` is 3.2 and the userland is BSD, so "works here" is never the claim. The claim is the line in the header that says which bash the script needs, and that line is checkable

The core below is what every script of the family shares, and each rule names the incident it was paid for. [`check-sh.sh`](check-sh.sh) beside this file is the mechanical half: it reads a script's dispatcher, parsers and exit codes out of the source and holds the help, the documents and the completions to them, in both directions, proving each of its own checks able to fail on every run

## The core

- **One shape for every script.** `#!/usr/bin/env bash`, a comment header whose usage lines are the help, `set -euo pipefail` with `-e` dropped only where findings are counted, `fail` and `die` through `printf … >&2`, one `mktemp -d` with a template under one `trap … EXIT`, and a `case "$cmd"` dispatcher at the bottom with an arm spelled `-h | --help | help)` and a `*)` arm that sends usage to stderr. Forty scripts in the family spelled each of these four ways, and a reader paid for each spelling. See [references/shape.md](references/shape.md)
- **The help is the single source of truth, and the code is held to it.** Every subcommand the dispatcher has, every flag a parser takes, every variable the script reads and every code it exits with appears in `--help`; comments say why, never how to call. A hand-written mirror — a README table, a layout line, a completion — is allowed because prose can be better than generated text, provided `check-sh.sh` diffs it against the dispatcher both ways. `log` shipped in `ci.sh` and stayed missing from every document until a review caught it. See [references/help.md](references/help.md)
- **Write for the bash macOS ships, and say so in the header.** `Needs bash 3.2 and POSIX tools only` is a claim the checker greps for and a macOS runner proves; a grep is a proxy that once let nine constructs through, so the proof is `/bin/bash ./check.sh behaviour` under the real 3.2. No `mapfile`, no `declare -A`, no `[[ -v`, no `${v^^}`, no `readlink -f`, no `sort -V`, no `grep -P`. A tool that needs 4.0 or 5.2 declares that instead, with the reason in one line. See [references/portability.md](references/portability.md)
- **Exit codes are a contract: 0 clean, 1 the thing asked about is wrong, 2 asked wrongly or nothing to check.** Two is what bash, coreutils, grep, curl, jq and argparse answer to an unknown flag, measured rather than assumed. `"${2:?…}"` exits 1 with bash's own message, so the guard is `(($# >= 2)) || die`. A harness whose 1 belongs to the command it runs takes the 64–89 band. See [references/shape.md](references/shape.md#exit-codes)
- **Human text to stderr, machine output to stdout, no colour, no `--json` flag.** A `status` subcommand prints one JSON line where a program needs one; emoji labels where a label is wanted. Then `tool | jq` works while refusals stay visible. See [references/shape.md](references/shape.md#streams-and-the-absence-of-decoration)
- **Probe the mechanism, never a proxy, and record the measurement.** `${#s}` is checked by a child `bash -c`, not by `wc -m`, because `wc` vouched for a locale bash never got. Every pitfall enters the standard as the command that showed it and its output, so the next reader re-measures instead of believing. See [references/pitfalls.md](references/pitfalls.md)
- **The agent's ad-hoc commands run in zsh; a script is judged by its shebang.** Arrays index from 1, `$pipestatus` replaces `PIPESTATUS`, `${v^^}` and `set -m` fail, `status` is read-only, `$h:r` eats a refspec. Verify bash behaviour with `bash -c '…'`, run a script as a file, never paste its body. See [references/harness.md](references/harness.md)
- **A tool a person types by hand gets completions, written by hand and drift-checked.** `.bash` and `#compdef` are the dialect markers; `check-sh.sh -c` holds both files to the parsers in both directions and refuses to pass on zero flags. The scripts an agent calls by path get none. See [references/completions.md](references/completions.md)
- **Never silence a linter where a rewrite satisfies it.** SC2251, SC2016, SC2100 and SC2207 all have rewrites, and the last one is also the bash 3.2 form; a `disable=` that survives carries its reason on the same line. When shfmt's opinion moves, the lock bump and the reformat land as one commit. See [references/lint.md](references/lint.md)

Following the letter of a rule while breaking its point is breaking the rule; the rules are short so the point can be read

## The checker

[`check-sh.sh`](check-sh.sh) is the mechanical half of the core, so following it costs less than not:

| Call | What it holds |
|---|---|
| `check-sh.sh SCRIPT` | the help to the dispatcher, the parsers and the exit codes, both ways; the header's bash 3.2 claim to a proxy grep |
| `check-sh.sh -e PREFIX SCRIPT` | every `PREFIX_*` variable the script reads to the help |
| `check-sh.sh -d DOC SCRIPT` | a document's `NAME sub` mentions and the flags it attaches to them, both ways; repeatable |
| `check-sh.sh -c BASH ZSH SCRIPT` | the two completion files to the dispatcher and the parsers, both ways |
| `check-sh.sh --template [script\|bash\|zsh]` | prints the canonical script, or its completions, which are what the checker plants its defects into |

Exit 0 when everything agrees, 1 with one line per finding, 2 when it was asked wrongly or there is nothing to check — a script with neither a dispatcher nor a flag arm is refused rather than passed. `check-sh.sh --help` carries the flags and the shapes it reads; [references/help.md](references/help.md) says what a help must contain for the checker to read it

## Taking the checker into another repository

`check-sh.sh` travels by the ci skill's vendoring cascade rather than by hand: `vendor-sync.sh add check-sh.sh rokokol/bash-best-practices-skill check-sh.sh` writes the copy and its lock line, the repository's gate calls the copy on each script it ships, and the weekly cascade brings every later fix. A fix to a copy belongs here, where every copy then gets it. A new script starts from `check-sh.sh --template`, and a repository whose script claims bash 3.2 takes [`templates/github/workflows/macos.yml`](templates/github/workflows/macos.yml) as its own workflow, so the claim gets its own badge. The mechanism is the ci skill's [vendored files](https://github.com/rokokol/ci-skill/blob/master/references/bump-cascade.md#vendored-files)

## Layout

```
SKILL.md              this file — the core, the checker, the layout
check-sh.sh           the checker: help ⇔ dispatcher ⇔ flags ⇔ codes ⇔ docs ⇔ completions, and the 3.2 proxy
references/           one spec per rule: shape, help, portability, pitfalls, harness, completions, lint; sources.md for the evidence
templates/            what check-sh.sh --template prints, held byte-equal by the gate; the macOS workflow a 3.2 claim earns
check.sh              this repo's own gate, self-tested against known-bad inputs, with a behaviour half that runs under bash 3.2
check-skill.sh        the gate every skill repository shares, vendored from the ci skill
check-pins.sh         the pin guard for the workflows, vendored from the ci skill
check-changelog.sh    the changelog checker, vendored from the versioning skill
vendor-sync.sh        keeps the vendored copies byte-equal to their source, vendored from the ci skill
tests/fixtures/       the constructs the proxy must catch, and the scripts the checker must refuse
```

What a green run proves belongs to the [tests](https://github.com/rokokol/tests-skill) skill, what gates a pull request and how a file travels to the [ci](https://github.com/rokokol/ci-skill) skill, the installer and its manifest to [huix-standard](https://github.com/rokokol/huix-standard-skill), and a changelog to [versioning](https://github.com/rokokol/versioning-skill); none of it is repeated here
