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

**zsh does not word-split an unquoted variable, and it reads `:h`, `:t`, `:r`, `:e` after one as history-style modifiers.** The first turns a separator-joined string into one field; the second eats text with no complaint at all, `$h:r` taken as "strip the extension". **Brace every expansion followed by punctuation**: it costs nothing in bash and is the difference between a refspec and a corrupted one in zsh

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

**An unquoted `*`, `?` or `[…]` that matches no file is an error, not a word, and after a command that is not a builtin the line runs on without it.** zsh's `NOMATCH` option, on by default and on in this harness, makes such a pattern "print an error, instead of leaving it unchanged in the argument list", where bash passes the text through. A URL with a query string is a pattern, and so is `find . -name *.sh` in a directory with no `.sh` in it. After a builtin such as `echo` the error ends the whole line with 1; after an external command only that command is dropped, the next one runs, and the line exits 0 — `find` never ran, and one line on stderr is all that says so. Quoting is the fix, `-name '*.sh'` and `'https://…?q=1'`:

```console
$ zsh -c 'echo https://example.com/?q=1'
zsh:1: no matches found: https://example.com/?q=1
$ bash -c 'echo https://example.com/?q=1'
https://example.com/?q=1
$ zsh -c 'echo pre; find . -maxdepth 0 -name *.nope; echo after'; echo "exit=$?"
pre
zsh:1: no matches found: *.nope
after
exit=0
$ zsh -c 'echo *.nope; echo after'; echo "exit=$?"
zsh:1: no matches found: *.nope
exit=1
$ zsh -c 'find . -maxdepth 0 -name "*.nope"; echo after'; echo "exit=$?"
after
exit=0
```

**`path` is `PATH` as an array, tied to it, so a loop that reads into `path` replaces the command search path.** `while read -r repo path` is the natural spelling for a list of repositories and their files, and in zsh every command after the first read is not found; `cdpath`, `fpath` and `manpath` are tied the same way, and bash has none of them. Quoting cannot help, since the name itself is the tie, so the fix is another name, `file` or `rel`:

```console
$ zsh -c 'typeset -p path cdpath fpath manpath' | sed 's/=(.*/=(…/'
typeset -aT PATH path=(…
typeset -aT CDPATH cdpath=(…
typeset -aT FPATH fpath=(…
typeset -aT MANPATH manpath=(…
$ zsh -c 'printf "a b\n" | while read -r repo path; do head -1 /dev/null; done; echo "status=$?"'
zsh:1: command not found: head
status=127
```

## What a background command is given

**A command the Bash tool runs in the background gets a socket on stdin that never reaches end of file, where a foreground command gets `/dev/null`.** Anything that reads stdin — `cat`, `read`, a tool that falls back to reading input when given no file, a nested run that inherits the shell's stdin — returns at once in the foreground and waits forever in the background, with nothing on stderr to say why. Give every background command that must not wait `</dev/null`:

```console
$ ls -l /proc/self/fd/0 | sed 's/.* -> //'; timeout 5 cat >/dev/null; echo "exit=$?"
/dev/null
exit=0
$ ls -l /proc/self/fd/0 | sed 's/.* -> //'; timeout 5 cat >/dev/null; echo "exit=$?"; timeout 5 cat </dev/null; echo "exit=$?"    # run_in_background
socket:[27132086]
exit=124
exit=0
```

**A pipeline lasts as long as its longest member, so `sleep N | cmd` runs N seconds after `cmd` is done.** `sleep` writes nothing, so it never meets the SIGPIPE that ends a producer whose reader has gone, and it is no way to hold a command's stdin open; `</dev/null` is the stdin that ends:

```console
$ s=$SECONDS; sleep 3 | true; echo "took $((SECONDS - s))s"
took 3s
```

## Rules

**Verify bash behaviour with `bash -c '…'`, never by typing the construct into the tool.** The tool's answer is zsh's answer, and the interesting cases — `${v^^}`, `PIPESTATUS`, `set -m`, array indices — are exactly where the two disagree. For the bash a macOS runner has, and what a local probe of it can and cannot settle, see [portability.md](portability.md#the-proxy-is-labelled-the-proof-is-a-run)

**Judge a script by its shebang, not by the shell that invoked it, and run it as a file rather than pasting its body into the tool.** A file beginning `#!/usr/bin/env bash` is bash whatever the agent is typing into, so "it failed in my shell" is not a finding about the script and "it worked in my shell" is not a pass ([shape.md](shape.md)). Pasting reinterprets every line under zsh and loses the whole class of differences above, along with `$0`, `BASH_SOURCE` and the `set -euo pipefail` the file opens with — `bash ./script.sh args` is the honest invocation, and `"$BASH" ./script.sh` inside a gate keeps nested runs on the interpreter the gate is proving

**`bash -n` and `zsh -n` are the parse checks, one per dialect.** A bash script is parse-checked with `bash -n`, a zsh completion with `zsh -n` and nothing else — shellcheck has no zsh dialect, and `bash -n` on a `#compdef` file reports syntax errors that are not ([completions.md](completions.md), [lint.md](lint.md))

**Keep separators quoted, or use `printf`.** Most of the differences above vanish under quoting — `"${h}:${b}"` rather than `$h:$b`, `"$v"` rather than `$v`, `'=1.2.3'` rather than `=1.2.3` — and `printf '%s\n'` with an explicit format is the portable way to emit a value, where `echo -n` is not portable at all

**A pattern the agent types can match the agent's own process.** `pkill -f TOKEN` from the Bash tool matches the zsh command line carrying `TOKEN` and ends the session's shell instead of the target; the measurement and the safe form are in [pitfalls.md](pitfalls.md)

## Next

The version floors behind the `bash -c` probes are in [portability.md](portability.md), and the zsh manual pages behind the measurements above in [sources.md](sources.md#the-harness)
