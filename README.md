<div align="center">

# bash-best-practices skill

**One shape, one truth, the bash macOS ships ʕ•ᴥ•ʔ**

[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![ci](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/build.yml)
[![macos](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/macos.yml/badge.svg)](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/macos.yml)

</div>

A shell script is read by three things: a person, its own `--help`, and a completion. The code is the only one of them that is executed, so the code is the only truth, and everything else — the help, a table in a readme, the words a completion offers — is held to it by a machine rather than by memory

The second truth is the machine the script runs on. These utilities travel to macOS, where `/bin/bash` is 3.2 and the userland is BSD, so "works here" is never the claim. The claim is the line in the header that says which bash the script needs, and that line is checkable. `check-sh.sh` beside the rules is the mechanical half, so following them costs less than not

## Contents

- [Install](#install)
- [The core](#the-core)
- [The checker](#the-checker)
- [Tests](#tests)
- [Layout](#layout)

## Install

```sh
git clone https://github.com/rokokol/bash-best-practices-skill ~/Projects/bash-best-practices
ln -s ~/Projects/bash-best-practices ~/.claude/skills/bash-best-practices
```

Or straight into the skills directory your agent reads:

```sh
git clone https://github.com/rokokol/bash-best-practices-skill ~/.claude/skills/bash-best-practices
```

> [!NOTE]
> A skill has no version to pin — it is read at whatever revision you have checked out, so `git pull` is the whole upgrade path and the changelog is dated rather than numbered

Then ask Claude Code to write, review or fix a shell script, or reach for it by name. [SKILL.md](SKILL.md) carries the rules and `references/` the reasoning and the measurements behind each

## The core

The rules live in [SKILL.md](SKILL.md#the-core), one line each with the incident it was paid for, and each points at the reference that carries the reasoning: the [shape](references/shape.md) every script shares, the [help](references/help.md) as the single source of truth, [portability](references/portability.md) to the bash 3.2 and BSD userland macOS ships, the [pitfalls](references/pitfalls.md) measured rather than remembered, the agent's zsh [harness](references/harness.md), [completions](references/completions.md) kept honest by machine, the [lint](references/lint.md) doctrine, and the [sources](references/sources.md) behind all of it

## The checker

`check-sh.sh` reads a script's dispatcher, its flag parsers, the variables it reads and the codes it exits with out of the source, and holds the help to them; with `-d DOC` it holds a document that lists the subcommands to the dispatcher both ways, with `-m DOC` only the mentions in a document that sends the reader to the help, with `-c BASH ZSH` the two completion files, and with `-e PREFIX` the environment variables. A header claiming `Needs bash X.Y` turns on a grep for the constructs that arrived after that floor, and `POSIX tools only` one for the flags a BSD userland lacks — both labelled as the proxy they are; the proof is the [macos.yml](templates/github/workflows/macos.yml) workflow running the gate under the real `/bin/bash` 3.2. `check-sh.sh --template` prints the canonical script and its two completions, which are the text the checker plants its defects into on every run

Another repository takes it through the ci skill's vendoring cascade, `vendor-sync.sh add check-sh.sh rokokol/bash-best-practices-skill check-sh.sh`, and calls the copy from its gate; `check-sh.sh --help` carries every flag and the shapes it reads

## Tests

`nix develop -c ./check.sh` runs the gate: the lint half holds the scripts, the workflows, the flake, the docs and the templates to their rules, and the behaviour half runs `check-sh.sh` on the skill's own scripts, proves the proxy on every construct in `tests/fixtures/bash4-constructs.sh`, proves the refusals, and silences one of the checker's findings at a time to prove its self-test notices. `/bin/bash ./check.sh behaviour` is the behaviour half alone, which is what the macOS job runs under the bash it ships, with `CHECK_BASH32=1` planting two constructs that only a 3.2 rejects. How to ask a 3.2 the same question before pushing, and what that local run does not prove, is in [portability.md](references/portability.md#the-proxy-is-labelled-the-proof-is-a-run)

## Layout

```
SKILL.md              the core, the checker, the layout
check-sh.sh           the checker: help ⇔ dispatcher ⇔ flags ⇔ codes ⇔ docs ⇔ completions, and the 3.2 proxy
references/           one spec per rule: shape, help, portability, pitfalls, harness, completions, lint; sources.md for the evidence
templates/            what check-sh.sh --template prints, held byte-equal by the gate; the macOS workflow a 3.2 claim earns
check.sh              this repo's own gate, self-tested against known-bad inputs, with a behaviour half that runs under bash 3.2
check-skill.sh        the gate every skill repository shares, vendored from the skill-authoring skill
check-pins.sh         the pin guard for the workflows, vendored from the ci skill
check-changelog.sh    the changelog checker, vendored from the versioning skill
vendor-sync.sh        keeps the vendored copies byte-equal to their source, vendored from the ci skill
tests/fixtures/       the constructs the proxy must catch, and the scripts the checker must refuse
```
