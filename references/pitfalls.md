# Pitfalls

Traps that cost a debugging session each, in bash itself and in the tools a script reaches for. Every entry is a command and its output, so the next reader re-measures it here instead of believing it, and a future bash, coreutils or `procps` that changes the answer is caught by re-running the block rather than by paying for the session again. Measured on this machine — bash 5.3, GNU coreutils 9.11, Linux — with the `bash:3.2` image beside it wherever an older bash disagrees. Traps about *which* machine a script lands on are in [portability.md](portability.md); traps that appear only when a command is typed into the agent's Bash tool are in [harness.md](harness.md)

## Signals and background jobs

**A background job started without job control has INT and QUIT set to ignore, and so does everything it spawns.** POSIX asks for that in a non-interactive shell, so a script that tests signal handling reports nothing at all off the foreground, and a watchdog cannot kill the tree it started — which on macOS, with no GNU `timeout`, is every watchdog (`tests/t.sh:974-976`). `set -m` gives each job its own process group and the default dispositions back; sixteen copies of a gate started with a plain `&` failed identically on a probe asserting 130, and the same sixteen under `set -m` were all clean (`tests/pitfalls.md:5-9`):

```console
$ bash -c 'p(){ sh -c "kill -INT \$\$"; echo "child exit=$?"; }; echo -n "plain &: "; p & wait; set -m; echo -n "set -m:  "; p & wait'
plain &: child exit=0
set -m:  child exit=130
```

**A re-raised signal still runs the EXIT trap.** The handler idiom is clean up, reset the trap, re-raise, and it is easy to assume the script then dies without EXIT running:

```console
$ bash -c 'trap "echo EXIT-trap-ran" EXIT; trap "echo INT-handler; trap - INT; kill -INT \$\$" INT; kill -INT $$'; echo "exit=$?"
INT-handler
EXIT-trap-ran
exit=130
```

So a copy planted to prove that the INT handler restores a file passes with the restore stripped from INT alone, because EXIT restores it instead — take the cleanup off every trap, or the test proves nothing (`tests/pitfalls.md:25-27`). The handler must also die rather than return: one that returns lets the loop carry on to the next item, and the interrupted one vanishes from the report (`tests/CHANGELOG.md`, "Ctrl-C did not stop `falsify`")

**`pkill -f PATTERN` matches the script's own command line.** The script was passed that string, or interpolated it into the pattern, so its argv holds it and `pkill` kills the caller along with the target:

```console
# reaper.sh   body: pkill -f 'my-daemon-token' || true; echo "still alive"
$ bash reaper.sh my-daemon-token; echo "exit=$?"
Terminated
exit=143
# reaper2.sh  body: self=$$; for p in $(pgrep -f 'my-daemon-token'); do [ "$p" = "$self" ] || kill "$p"; done; echo "still alive"
$ bash reaper2.sh my-daemon-token; echo "exit=$?"
still alive
exit=0
```

Nothing after the `pkill` runs, the cleanup is skipped, and the caller sees a signal death rather than a failure — observed as exit 144 out of a whole tool chain on 2026-09-10, because every ancestor carrying the token died too, the agent's own shell included while this was being measured. **Kill by PID, or filter `$$` out of `pgrep -f`**

**`pgrep -x` cannot see a program whose name is longer than 15 characters**, because `comm` is the kernel's truncated copy of it. `procps` says so rather than answering "no such process", which is the only mercy here:

```console
$ cp "$(command -v bash)" ./very-long-sleeper-name     # 22 characters
$ ./very-long-sleeper-name -c 'sleep 5; :' & sleep 0.3; cat /proc/$!/comm
very-long-sleep
$ pgrep -x 'very-long-sleeper-name'
pgrep: pattern that searches for process name longer than 15 characters will result in zero matches
Try `pgrep -f' option to match against the complete command line.
```

**`pgrep -f` is the way out, and it matches argv as it was written rather than as it resolves**, so a child started from a relative path is invisible to its absolute one — `pgrep -f /tmp/w/very-long-sleeper-name` exits 1 where `pgrep -f './very-long-sleeper-name'` prints the PID; a supervisor either remembers how it started the child or, better, keeps the PID

## Streams

**A command that reads stdin inside a `while read` loop eats the loop's input.** The loop below is the obvious way to visit every line, and it visits one:

```console
$ printf 'one\ntwo\nthree\n' > list
$ while IFS= read -r f; do cat >/dev/null; echo "visited $f"; done < list | wc -l
1
$ while IFS= read -r f; do cat </dev/null >/dev/null; echo "visited $f"; done < list | wc -l
3
```

No error, no warning, just an early end and a plausible result for the first item. The same measured against a real CLI: 1296 lines in, 1 answer out, 3 ms instead of 1.5 s (`obsidian-cli/references/pitfalls.md:60-79`). **Give every call inside such a loop `</dev/null`** unless it is deliberately being fed, and the same for `xargs` and `find -exec … \;`

**`| xargs` as a whitespace trim runs `echo` and strips quotes.** It looks like a trim with no dependencies and it is two mines: `xargs` with no command runs `echo`, so anything option-shaped is read as a flag by that `echo`, and `xargs` applies its own quoting rules to the input:

```console
$ echo " --help " | xargs; echo "exit=$?"
Usage: …/echo [SHORT-OPTION]... [STRING]...    # …and 30 more lines of coreutils help
exit=0
$ echo "don't" | xargs; echo "exit=$?"
xargs: unmatched single quote; by default quotes are special to xargs unless you use the -0 option
exit=1
```

The first is worse than the second: exit 0, and a screen of help where a trimmed `--help` was expected. **Trim with `tr -s '[:space:]' ' '` and a pair of `${s# }`/`${s% }`** — `printf '  a  b  ' | tr -s '[:space:]' ' '` gives `[ a b ]`, no subprocess and no surprises

**`IFS=$'\t' read` drops an empty field, because a tab is IFS white space.** POSIX puts space, tab and newline in one class, a run of them is a single delimiter and a leading or trailing run delimits nothing; only an IFS character outside that class, such as `,`, delimits an empty field. An empty column of a tab-separated line therefore vanishes and every column after it moves one to the left — the same in bash 5.3, bash 3.2 and zsh:

```console
$ printf 'a\t\tc\n' | { IFS=$'\t' read -r x y z; printf '[%s][%s][%s]\n' "$x" "$y" "$z"; }
[a][c][]
$ printf 'a,,c\n' | { IFS=, read -r x y z; printf '[%s][%s][%s]\n' "$x" "$y" "$z"; }
[a][][c]
$ printf 'a\t\tc\n' | awk -F '\t' '{ printf "[%s][%s][%s]\n", $1, $2, $3 }'
[a][][c]
```

It hides while the empty fields are the last ones on the line and surfaces the day a column is added after them: in the contributing skill's `contrib.sh`, a new column slid into an empty "last seen" field and made new items look already marked (measured there 2026-09-11). **Never emit an empty tab-separated field — `jq`'s `// "-"` gives it a placeholder — or split the line with `awk -F '\t'`**, which does not fold (gawk and busybox awk measured)

## The interpreter

**bash reads a script while it runs, so an in-place rewrite lands mid-execution.** The running copy reads on from the byte offset it had reached, and in a truncated file there is nothing there:

```console
$ printf '#!/usr/bin/env bash\necho "line 2"\nsleep 0.3\necho "line 4"\n' > r.sh
$ bash r.sh & sleep 0.1; printf '#!/usr/bin/env bash\necho NEW\n' > r.sh; wait
line 2
$ printf '#!/usr/bin/env bash\necho "line 2"\nsleep 0.3\necho "line 4"\n' > r.sh   # restored
$ bash r.sh & sleep 0.1; printf '#!/usr/bin/env bash\necho NEW\n' > r.new; mv r.new r.sh; wait
line 2
line 4
```

Line 4 simply vanished. **Any updater that touches a script — a vendoring cascade, an installer, a self-update — writes a new file and `mv`s it over the old one**, which is why `vendor-sync.sh` replaces a copy rather than rewriting it, its own file included (`ci/references/bump-cascade.md:38`)

**`${2:?message}` exits 1 with bash's message, not the script's.** It reads like an argument check and it is a different contract: 1 is this family's code for "the thing asked about is wrong", a usage error is 2, and the text names the parameter by number rather than the tool by name:

```console
$ printf '#!/usr/bin/env bash\n: "${2:?the second argument}"\necho unreachable\n' > q.sh
$ bash q.sh one; echo "exit=$?"
q.sh: line 2: 2: the second argument
exit=1
```

`docker run --rm -v "$PWD":/w -w /w bash:3.2 bash q.sh one` answers identically, so this is not a version to grow out of. **The guard is `(($# >= 2)) || die "usage: …"`**, with `die` printing to stderr and exiting 2 — the codes and the helpers are in [shape.md](shape.md), the text the help must carry in [help.md](help.md). No literal `exit` gives it away, so `check-sh.sh` reports every `${N:?}` outside a comment: `t.sh` had twenty-three, each answering a mistyped call with the code a failing test exits

**Deciding interactivity by `[[ -t 0 ]]` hangs the script under a pty.** `ssh -t`, an expect wrapper and every terminal multiplexer hand a script a tty on stdin with nobody there to type, and a script that takes that for a person reaches `read -rp` and waits forever with nothing on screen to say what for — an installer did exactly that on 2026-09-03 (3x-ui `install.sh`). **A non-interactive run is declared, not detected**: a flag or an environment variable turns the prompts off, `[[ -t 0 ]]` may only *add* a prompt that already has a default, and a caller that wants none passes `</dev/null` as well

## The tools around it

**shellcheck sees every local in a file at once**, so a name used as an array in one function and as a scalar in another is a mistake to it, and the warning points at the *other* use, which is why it reads as unrelated. Adding one subcommand to `t.sh` cost three renames on that alone — `set` shadowed the builtin, `first` was a scalar elsewhere, `cmd` was the dispatcher's own variable at the bottom of the file (`tests/pitfalls.md:21-23`). Pick names nothing else in the file uses, and run `shellcheck` before running anything else ([lint.md](lint.md))

**Judge `grep` by what it says, not by its status.** A regex `grep` cannot compile is not a uniform failure: GNU and BSD `grep` exit 2, busybox's does not compile it until there is a line to match, and all of them complain on stderr once it does. An excuse-list regex applied with `grep -Ev` and judged by status left the filtered log empty, an empty log has no findings, and every run reported a pass (`tests/t.sh:260-265`, `tests/CHANGELOG.md:28`). Feed the probe a line of input rather than `/dev/null`, capture stderr, and treat a complaint as the answer

**An undefined `awk` escape is noise, not a difference.** `\ ` for a space is undefined by POSIX and it is tempting to read that as a portability defect: gawk, mawk, busybox awk, goawk and the one-true-awk macOS ships were each run over the four shapes the pattern had to read, and all five agree it is a space (`tests/pitfalls.md:33-35`). The real cost was twenty-nine warnings on stderr in a run ending `check: everything holds`. Fix it for the noise, and do not invent a portability story that measurement does not support — the same discipline that keeps the bash floor honest in [portability.md](portability.md). **An `exit N` inside an `awk` program is awk's status, not the script's**, which is why `check-sh.sh` counts only bash-shaped ones — `exit N` followed by `;`, end of line, `&&` or `||` — and leaves `{ exit 1 }` alone: `t.sh:657` ends its awk program that way to say "no table found", and the shell's own code for that case is the `die` on the line that reads the substitution

**`awk -v` runs escape processing over the value, so a regex passed that way loses its backslashes.** POSIX reads a `-v` value as if it stood between double quotes in the program, so `\t` turns into a tab in every awk measured, and `\.` — an escape POSIX leaves undefined — turns into a plain `.` in gawk, busybox awk and the one-true-awk macOS ships, while mawk keeps the backslash. Here the undefined escape of the entry above does change the answer:

```console
$ awk -v re='a\.b' 'BEGIN { print ("axb" ~ re) }'
awk: warning: escape sequence `\.' treated as plain `.'
1
$ RE='a\.b' awk 'BEGIN { print ("axb" ~ ENVIRON["RE"]) }'
0
```

The dot now matches any character, and the only trace is gawk's warning on stderr — the one-true-awk and busybox print none — so a suite that reads stdout alone sees a pattern that quietly matches too much. **Hand data to awk through the environment and read `ENVIRON["NAME"]`**: POSIX makes each element the variable's value as it is, all four awks agree, and `check-sh.sh` plants its defects that way (`check-sh.sh:651,655`) after a `-v` pass mangled the backslashes of a planted line. A gate that runs awk over its own patterns can also require a clean run to leave stderr empty, which is how the contributing skill's gate now catches it

## Next

The manuals and wiki pages behind each entry are in [sources.md](sources.md#pitfalls); whether a check like these would ever notice a regression belongs to the [tests](https://github.com/rokokol/tests-skill) skill
