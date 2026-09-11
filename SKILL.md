---
name: bash-best-practices
description: "What it is — a standard for the author's sh and bash utilities: one script shape, help as the single source of truth for a CLI, portability to the bash 3.2 and BSD userland macOS ships, measured pitfalls, the traps of an agent's zsh harness, tab completions kept honest by machine, shellcheck and shfmt doctrine, and check-sh.sh, one travelling checker that holds a script's help, docs and completions to its dispatcher. Use when writing, reviewing or refactoring any shell script or CLI wrapper, adding a subcommand, a flag or a completion, deciding which bash a script needs, making a script run on macOS, running ad-hoc shell commands from the Bash tool, or reading a shellcheck or shfmt finding. Triggers: bash, sh, shell script, shebang, set -euo pipefail, usage, --help, subcommand, completion, compdef, shellcheck, shfmt, macOS, BSD, bash 3.2, readlink -f, mktemp, mapfile, zsh, pipefail, скрипт, баш, шелл, напиши скрипт, справка, подкоманда, автодополнение, совместимость с macOS, шеллчек."
license: MIT
---

# bash-best-practices

A shell script is read by three things: a person, its own `--help`, and a completion. The code is the only one of them that is executed, so the code is the only truth, and everything else — the help, a table in a readme, the words a completion offers — is held to it by a machine rather than by memory. Two accounts of one thing disagree within a month; a list nobody checks is a list that has already drifted

The second truth is the machine the script runs on. These utilities travel to macOS, where `/bin/bash` is 3.2 and the userland is BSD, so "works here" is never the claim. The claim is the line in the header that says which bash the script needs, and that line is checkable

## Layout

```
SKILL.md              this file — the core, the checker, the layout
check.sh              this repo's own gate, self-tested against known-bad inputs
check-skill.sh        the gate every skill repository shares, vendored from the ci skill
check-pins.sh         the pin guard for the workflows, vendored from the ci skill
check-changelog.sh    the changelog checker, vendored from the versioning skill
vendor-sync.sh        keeps the vendored copies byte-equal to their source, vendored from the ci skill
```
