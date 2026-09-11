<div align="center">

# bash-best-practices skill

**One shape, one truth, the bash macOS ships ʕ•ᴥ•ʔ**

[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![ci](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/bash-best-practices-skill/actions/workflows/build.yml)

</div>

A shell script is read by three things: a person, its own `--help`, and a completion. The code is the only one of them that is executed, so the code is the only truth, and everything else — the help, a table in a readme, the words a completion offers — is held to it by a machine rather than by memory

The second truth is the machine the script runs on. These utilities travel to macOS, where `/bin/bash` is 3.2 and the userland is BSD, so "works here" is never the claim. The claim is the line in the header that says which bash the script needs, and that line is checkable

## Contents

- [Install](#install)
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

Then ask Claude Code to write, review or fix a shell script, or reach for it by name. [SKILL.md](SKILL.md) carries the rules

## Layout

```
SKILL.md              the core, the checker, the layout
check.sh              this repo's own gate, self-tested against known-bad inputs
check-skill.sh        the gate every skill repository shares, vendored from the ci skill
check-pins.sh         the pin guard for the workflows, vendored from the ci skill
check-changelog.sh    the changelog checker, vendored from the versioning skill
vendor-sync.sh        keeps the vendored copies byte-equal to their source, vendored from the ci skill
```
