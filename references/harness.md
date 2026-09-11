# The agent's shell is not the script's shell

The Claude Code Bash tool runs each ad-hoc command under the user's login shell, which on this machine is zsh — so a snippet that fails when the agent types it may be perfectly good bash, and one that works may be no evidence at all. This file records what was measured on that harness and the rules that follow; every block below is a command run through the Bash tool itself, with its output

```console
$ echo "ZSH_VERSION=$ZSH_VERSION BASH_VERSION=$BASH_VERSION"; ps -o comm= $$; echo "$0"
ZSH_VERSION=5.9.2 BASH_VERSION=
zsh
/run/current-system/sw/bin/zsh
```

## What zsh does differently

**Arrays index from 1, and so does `$pipestatus`, which is what zsh calls `PIPESTATUS`.** These are the differences that produce a plausible wrong answer rather than an error, so they are the ones that survive into a conclusion:

```console
$ zsh -c 'a=(x y); echo ${a[1]}'
x
$ bash -c 'a=(x y); echo ${a[1]}'
y
$ zsh -c 'true | false | true; echo "PIPESTATUS=${PIPESTATUS[@]-unset} pipestatus=${pipestatus[@]}"'
PIPESTATUS=unset pipestatus=0 1 0
$ bash -c 'true | false | true; echo "PIPESTATUS=${PIPESTATUS[@]}"'
PIPESTATUS=0 1 0
```

**Four that fail loudly, and are therefore harmless once recognised:**

```console
$ zsh -c 'v=abc; echo ${v^^}'        # case modification is bash 4.0, and not zsh syntax at all
zsh:1: bad substitution
$ zsh -c 'set -m; echo ok'           # job control cannot be turned on non-interactively
zsh:set:1: can't change option: -m
$ zsh -c 'echo =foo'                 # an unquoted leading = is an equals-expansion
zsh:1: foo not found
$ zsh -c 'true; status=$?'           # zsh's own $? lives in $status, which is read-only
zsh:1: read-only variable: status
```

`status=$?` is ordinary bash and an error in zsh, so `rc=$?` is the spelling that survives both; `=foo` bites whenever a command line carries a word starting with `=` — a version pin, an `awk` assignment, a `--flag=value` split by accident — and quoting is the fix, as it is for most of what follows

**zsh does not word-split an unquoted variable, and it reads `:h`, `:t`, `:r`, `:e` after one as history-style modifiers.** The first turns a separator-joined string into one field; the second eats text with no complaint at all — ten pushes failed on 2026-09-10 because a refspec was built this way, `$h:r` taken as "strip the extension". **Brace every expansion followed by punctuation**: it costs nothing in bash and is the difference between a refspec and a corrupted one in zsh

```console
$ zsh -c 'v="a b"; printf "[%s]\n" $v'
[a b]
$ bash -c 'v="a b"; printf "[%s]\n" $v'
[a]
[b]
$ zsh -c 'h=e499e4fe; b=master; echo "$h:refs/heads/$b"'
e499e4feefs/heads/master
$ zsh -c 'h=e499e4fe; b=master; echo "${h}:refs/heads/${b}"'
e499e4fe:refs/heads/master
```

## Rules

**Verify bash behaviour with `bash -c '…'`, never by typing the construct into the tool.** The tool's answer is zsh's answer, and the interesting cases — `${v^^}`, `PIPESTATUS`, `set -m`, array indices — are exactly where the two disagree. For the bash a macOS runner has, the probe is `docker run --rm bash:3.2 bash -c '…'`, whose userland is busybox rather than BSD, so it settles the interpreter and nothing else ([portability.md](portability.md))

**Judge a script by its shebang, not by the shell that invoked it, and run it as a file rather than pasting its body into the tool.** A file beginning `#!/usr/bin/env bash` is bash whatever the agent is typing into, so "it failed in my shell" is not a finding about the script and "it worked in my shell" is not a pass ([shape.md](shape.md)). Pasting reinterprets every line under zsh and loses the whole class of differences above, along with `$0`, `BASH_SOURCE`, the header the help is extracted from and the `set -euo pipefail` the file opens with — `bash ./script.sh args` is the honest invocation, and `"$BASH" ./script.sh` inside a gate keeps nested runs on the interpreter the gate is proving (`tests/check.sh:42-45`)

**`bash -n` and `zsh -n` are the parse checks, one per dialect.** A bash script is parse-checked with `bash -n`, a zsh completion with `zsh -n` and nothing else — shellcheck has no zsh dialect, and `bash -n` on a `#compdef` file reports syntax errors that are not ([completions.md](completions.md), [lint.md](lint.md))

**Keep separators quoted, or use `printf`.** Most of the differences above vanish under quoting — `"${h}:${b}"` rather than `$h:$b`, `"$v"` rather than `$v`, `'=1.2.3'` rather than `=1.2.3` — and `printf '%s\n'` with an explicit format is the portable way to emit a value, where `echo -n` is not portable at all

**A pattern the agent types can match the agent's own process.** `pkill -f TOKEN` from the Bash tool matches the zsh command line carrying `TOKEN` and ends the session's shell instead of the target; the measurement and the safe form are in [pitfalls.md](pitfalls.md)

## Next

The version floors behind the `bash -c` probes are in [portability.md](portability.md), and the zsh manual pages behind the measurements above in [sources.md](sources.md#the-harness)
