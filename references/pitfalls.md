# Pitfalls

Traps that cost a debugging session each, in bash itself and in the tools a script reaches for. Every entry is a command and its output, so the next reader re-measures it here instead of believing it, and a future bash, coreutils or `procps` that changes the answer is caught by re-running the block rather than by paying for the session again. Measured on this machine — bash 5.3, GNU coreutils 9.11, Linux — with the `bash:3.2` image beside it wherever an older bash disagrees. Traps about *which* machine a script lands on are in [portability.md](portability.md); traps that appear only when a command is typed into the agent's Bash tool are in [harness.md](harness.md)

## Signals and background jobs

**A background job started without job control has INT and QUIT set to ignore, and so does everything it spawns.** POSIX asks for that in a non-interactive shell, so a script that tests signal handling reports nothing at all off the foreground, and a watchdog cannot kill the tree it started — which on macOS, with no GNU `timeout`, is every watchdog. `set -m` gives each job its own process group and the default dispositions back:

```console
$ bash -c 'p(){ sh -c "kill -INT \$\$"; echo "child exit=$?"; }; echo -n "plain &: "; p & wait; set -m; echo -n "set -m:  "; p & wait'
plain &: child exit=0
set -m:  child exit=130
```

**An ignore inherited from before the script started stays, whatever the script does.** A script run from a job that was itself started with `&` gets INT already ignored: `set -m` gives nothing back then, and `trap - INT` restores the default in bash 5.3 but not in bash 4.4, 3.2, dash 0.5.13 or busybox sh, which keep to POSIX's rule that a non-interactive shell cannot reset a signal ignored on entry. A check that sends a real INT to a child reads green in a terminal and red under `&`. One that only reads the status writes `exit 130`, which no disposition changes; one that needs the signal itself sends it to a child `sh` first and refuses to run when the child survives, rather than going red on correct code:

```console
$ docker run --rm bash:4.4 sh -c 'bash -c '\''sh -c "kill -INT \$\$"; echo "plain:      $?"; (set -m; sh -c "kill -INT \$\$" & wait $!; echo "set -m:     $?"); bash -c "trap - INT; kill -INT \$\$"; echo "trap - INT: $?"'\'' & wait'
plain:      0
[1]+  Done                    sh -c "kill -INT \$\$"
set -m:     0
trap - INT: 0
```

The same line with `bash:5` prints `trap - INT: 130` and nothing else changes

**A re-raised signal still runs the EXIT trap.** The handler idiom is clean up, reset the trap, re-raise, and it is easy to assume the script then dies without EXIT running:

```console
$ bash -c 'trap "echo EXIT-trap-ran" EXIT; trap "echo INT-handler; trap - INT; kill -INT \$\$" INT; kill -INT $$'; echo "exit=$?"
INT-handler
EXIT-trap-ran
exit=130
```

So a copy planted to prove that the INT handler restores a file passes with the restore stripped from INT alone, because EXIT restores it instead — take the cleanup off every trap, or the test proves nothing. The handler must also die rather than return: one that returns lets the loop carry on to the next item, and the interrupted one vanishes from the report

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

Nothing after the `pkill` runs, the cleanup is skipped, and the caller sees a signal death rather than a failure; every ancestor carrying the token can die too, including the agent's own shell. **Kill by PID, or filter `$$` out of `pgrep -f`**

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

**A trapped signal waits for the command bash is in, and one expansion can last minutes.** bash notes the signal and runs the trap between commands, so a script that traps TERM for its cleanup is not stopped by TERM while a single long expansion runs, and a watchdog's TERM takes effect only when that expansion ends. Untrapped, TERM kills at once, and KILL cannot be trapped at all:

```console
$ for how in 'TERM, no trap' 'TERM, trapped' 'KILL, trapped'; do
>   trap=''; [[ $how == *trapped ]] && trap='trap "exit 0" TERM'
>   bash -c "$trap"'
>     t=$(awk "BEGIN { for (i = 0; i < 8000; i++) printf \"line %05d of filler text\n\", i; print \"needle\" }")
>     : "${t#*needle}"' &
>   sleep 2; s=$SECONDS; kill -"${how%%,*}" $!; wait $! 2>/dev/null
>   echo "$how: gone $((SECONDS - s)) s after the signal"
> done
TERM, no trap: gone 0 s after the signal
TERM, trapped: gone 19 s after the signal
KILL, trapped: gone 0 s after the signal
```

`bash:3.2` answers 0, 35 and 0 s. **A watchdog that must stop a bash script on time sends KILL**, and gives up the cleanup the trap would have done, which is acceptable only where what the run leaves behind is thrown away, such as a fixture under a work directory; where the cleanup matters, keep the long work out of a single expansion instead

## Streams

**A command that reads stdin inside a `while read` loop eats the loop's input.** The loop below is the obvious way to visit every line, and it visits one:

```console
$ printf 'one\ntwo\nthree\n' > list
$ while IFS= read -r f; do cat >/dev/null; echo "visited $f"; done < list | wc -l
1
$ while IFS= read -r f; do cat </dev/null >/dev/null; echo "visited $f"; done < list | wc -l
3
```

No error, no warning, just an early end and a plausible result for the first item. **Give every call inside such a loop `</dev/null`** unless it is deliberately being fed, and the same for `xargs` and `find -exec … \;`

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

It hides while the empty fields are the last ones on the line and surfaces when a column is added after them, shifting every later value left. **Never emit an empty tab-separated field — `jq`'s `// "-"` gives it a placeholder — or split the line with `awk -F '\t'`**, which does not fold

**A text far smaller than the pipe buffer still leaves in more than one `write()`, so `producer | grep -q` is a race rather than a safe pipeline.** bash line-buffers stdout whatever it is connected to — `shell_initialize()` calls `sh_setlinebuf(stdout)` — and the `printf` builtin prints through `putchar`, so the C library decides where the text is cut: glibc flushes at every newline, musl writes the body in one chunk and the closing newline on its own, and the libc macOS ships flushes whenever the character is a newline and the stream is line buffered. Two writes are enough for the accident: `grep -q` matches in the first, exits, and the second meets a pipe with no reader:

```console
$ strace -f -e trace=write bash -c 'printf "%s\n" "$text" | cat >/dev/null'   # glibc, 235 bytes
write(1, "case \"$cmd\" in\n", 15)
write(1, "  run) cmd_run \"$@\" ;;\n", 23)
…                                                # nine writes, one per line
$ docker run --rm -v "$PWD:/w" bash:3.2 …        # musl, the same 235 bytes
write(1, "case \"$cmd\" in\n  run) cmd_run \"$@\"…", 234)
write(1, "\n", 1)
```

How often the second write loses the race is a matter of scheduling, so a short text fails rarely rather than never, which is why this reaches CI instead of the first run. The same pipeline, 300 runs each, with the pattern matching early in the text:

| The text | glibc, bash 5.3 | musl, bash 3.2 |
|---|---|---|
| 235 bytes | 0 of 80000 | 0 of 300 |
| 7.9 KB | 1 of 300 | 1 of 300 |

**A producer that is not the shell writes in blocks, not in lines, and that moves the threshold rather than removing it.** GNU `cat` fills a 128 KiB buffer per `write()`, so it usually finishes before the reader can exit: `cat FILE | head -n1` under `pipefail` survived 200 of 200 runs at every size up to 384 KB, went to 33 of 200 at 512 KB, and failed 200 of 200 from 1 MB up, on glibc with a 64 KiB pipe. The pipe buffer is not the boundary — what decides is how many `write()` calls the producer still owes when the reader goes. So neither a small text nor a fast tool is a defence, and "this one is not a shell builtin" is not a reason to leave the pipeline standing

A 50 ms delay in the place the scheduler occupies makes it certain, and shows the two directions the mistake takes: `! … | grep -q` reports a finding that is not there, and `… | grep -q || flag=1` silently switches a check off:

```console
$ bash -c 'set -o pipefail; { printf "%s\n" "$text"; sleep 0.05; printf "x\n"; } | grep -q "help)"; echo "status=$?"'
status=141
$ bash -c 'set -o pipefail; v=$text; grep -q "help)" <<<"$v"; echo "status=$?"'
status=0
```

**Give the text to the reader with `<<<`**, which is a temporary file and has no producer to kill, and where a pipeline must stay, let the consumer read to the end — `sed -n 1p` rather than `head -1`, `!seen { … seen = 1 }` rather than `awk … exit`. Measured in the wild: one macOS CI run in about 180 across six repositories rejected a script its own self-test had just written, and the run after it passed on the same bytes

## The interpreter

**`<<` opens a heredoc everywhere except inside `$(( ))`, where it is a left shift.** The same four characters are two constructs, and only the surrounding arithmetic tells them apart, so anything reading shell text rather than parsing it takes the word after the shift for a terminator. That terminator never arrives, and the reader treats the rest of the file as heredoc body — which is silent, because a scanner that has swallowed a file reports nothing wrong about it. Read the text with a parser, `shfmt --to-json` or `bash --pretty-print`; where a scan is all there is, count `$((` depth and open no heredoc inside one:

```console
$ printf '%s\n' 'n=$((1<<k))' 'case "$cmd" in' '  run) : ;;' 'esac' > naive.sh
$ awk 'match($0, /<<-?[A-Za-z_][A-Za-z0-9_]*/) { print NR ": terminator = " substr($0, RSTART + 2, RLENGTH - 2) }' naive.sh
1: terminator = k
$ grep -cx k naive.sh
0
```

The scan takes `k` for a terminator, no line is ever `k`, and everything from the shift onward is read as heredoc body — the dispatcher included. Nothing about that is visible in the output: the reader simply finds no dispatcher, and a count of zero is not a complaint

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

Line 4 simply vanished. **Any updater that touches a script — a vendoring cascade, an installer, a self-update — writes a new file and `mv`s it over the old one**

**Under `bash <(…)` a script's own path is the pipe bash is reading it from.** Process substitution hands bash a path such as `/proc/self/fd/12`, and `"${BASH_SOURCE[0]}"` is that path. bash reads a script from a pipe no further than the command it is about to run, so a reader that opens the path gets the rest of the file after that command, and bash, meeting EOF, never runs it:

```console
$ printf '%s\n' '#!/usr/bin/env bash' 'cat "${BASH_SOURCE[0]}"' 'echo AFTER' >g.sh
$ bash <(cat g.sh); echo "exit=$?"
echo AFTER
exit=0
```

A `usage()` called from the dispatcher at the bottom therefore finds nothing left and prints nothing at exit 0, and a reader that runs earlier takes the rest of the program, here 28900 bytes of it:

```console
$ printf '%s\n' '#!/usr/bin/env bash' '# m.sh — the help is this header' 'sed -n "2,/^[^#]/p" "${BASH_SOURCE[0]}" | wc -c' >m.sh
$ { cat m.sh; for i in $(seq 2000); do echo "# padding $i"; done; echo 'echo "END reached"'; } >big.sh
$ bash m.sh; bash <(cat m.sh); echo "exit=$?"
83
0
exit=0
$ bash big.sh; bash <(cat big.sh); echo "exit=$?"
83
END reached
28900
exit=0
```

`bash:3.2` answers identically. `bash -s <m.sh` at least fails aloud, since `BASH_SOURCE[0]` is then no path at all. **The help is a heredoc, never the header read back out of the file** ([help.md](help.md)), and `check-sh.sh` runs every script's help through such a pipe and reports one that exits 0 with other text than the file's

**`${2:?message}` exits 1 with bash's message, not the script's.** It reads like an argument check and it is a different contract: 1 is this family's code for "the thing asked about is wrong", a usage error is 2, and the text names the parameter by number rather than the tool by name:

```console
$ printf '#!/usr/bin/env bash\n: "${2:?the second argument}"\necho unreachable\n' > q.sh
$ bash q.sh one; echo "exit=$?"
q.sh: line 2: 2: the second argument
exit=1
```

`docker run --rm -v "$PWD":/w -w /w bash:3.2 bash q.sh one` answers identically, so this is not a version to grow out of. **The guard is `(($# >= 2)) || die "usage: …"`**, with `die` printing to stderr and exiting 2 — the codes and the helpers are in [shape.md](shape.md), the text the help must carry in [help.md](help.md). No literal `exit` gives it away, so `check-sh.sh` reports every `${N:?}` outside a comment

**`cmd && action` as the last command of a function ends a `set -e` script in silence.** `set -e` ignores a failure on the left of `&&`, so at the top level a `grep` that finds nothing just moves on. As a function's last command the same line's status is the function's, and the call is a plain command that `set -e` does act on:

```console
$ printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'check() {' '  echo "checking"' '  grep -q never /dev/null && echo "found"' '}' 'check' 'echo "all checks passed"' > e.sh
$ bash e.sh; echo "exit=$?"
checking
exit=1
```

`bash:3.2` answers identically. It bites when sections of a script move into functions — a gate split into halves — because a line that was harmless at the top level becomes a function's status without being touched. **Write the guard as `if cmd; then action; fi`**, whose status is 0 when `cmd` fails

**Deciding interactivity by `[[ -t 0 ]]` hangs the script under a pty.** `ssh -t`, an expect wrapper and every terminal multiplexer hand a script a tty on stdin with nobody there to type, and a script that takes that for a person reaches `read -rp` and waits forever. **A non-interactive run is declared, not detected**: a flag or an environment variable turns the prompts off, `[[ -t 0 ]]` may only *add* a prompt that already has a default, and a caller that wants none passes `</dev/null` as well

**A backslash inside a double-quoted `${x:+word}` stays literal, so escaping a character there changes the value rather than protecting it.** The word of `:+`, `:-` and `:=` is already inside the quotes, and bash keeps a backslash that precedes anything but `$`, `` ` ``, `"`, `\` or a newline. The reflex costs a session when a tool refuses the bare character — tree-sitter's bash grammar rejects a bare `|`, `&`, `;` or `>` there, which is [tree-sitter-bash#267](https://github.com/tree-sitter/tree-sitter-bash/issues/267) — because the escape silences the tool and the string quietly grows a backslash. Closing the quotes around the character alone is what keeps the value:

```console
$ bash -c 'p=A; q=B; printf "bare   %s\n" "${p:+$p|}$q"; printf "esc    %s\n" "${p:+$p\|}$q"; printf "quoted %s\n" "${p:+$p"|"}$q"'
bare   A|B
esc    A\|B
quoted A|B
```

The same three lines print the same three answers under `bash:3.2`. A workaround for a parser is measured against the shell, never against the parser that asked for it

**Every removal pattern costs the square of the string's length, the anchored one too.** `${t#*needle}` and `${t%%needle*}` both try the pattern at each position against the rest of the string, so four times the text costs sixteen times as much; the suffix form only has the smaller constant, which one timing at one size reads as a different order. A containment test stays linear:

```console
$ for n in 2000 8000; do
>   t=$(awk -v n=$n 'BEGIN { for (i = 0; i < n; i++) printf "line %05d of filler text\n", i; print "needle" }')
>   TIMEFORMAT="$n lines  prefix removal  %3R s"; time : "${t#*needle}"
>   TIMEFORMAT="$n lines  suffix removal  %3R s"; time : "${t%%needle*}"
>   TIMEFORMAT="$n lines  containment     %3R s"; time [[ $t == *needle* ]]
> done
2000 lines  prefix removal  1.283 s
2000 lines  suffix removal  0.009 s
2000 lines  containment     0.000 s
8000 lines  prefix removal  20.691 s
8000 lines  suffix removal  0.156 s
8000 lines  containment     0.001 s
```

`bash:3.2` grows the same way: 2.351 to 37.469 s for the prefix, 0.066 to 1.024 s for the suffix, 0.001 to 0.003 s for containment, and a substring `${t:n}` and a length `${#t}` measured alongside grew about fourfold. **To find where a string sits in a large text, halve the length of a prefix that still contains it** — `[[ ${t:0:mid} == *"$s"* ]]` — which is log2 of the length in linear steps, and judge any claim of linearity by the ratio between two sizes, never by one timing

## The tools around it

**shellcheck sees every local in a file at once**, so a name used as an array in one function and as a scalar in another is a mistake to it, and the warning points at the *other* use, which is why it reads as unrelated. Pick names nothing else in the file uses, and run `shellcheck` before running anything else ([lint.md](lint.md))

**A comment whose text opens with `shellcheck` is read as a directive to shellcheck, so where the word sits on the line decides whether the file lints.** Prose that names the tool is ordinary prose until a rewrap moves the word to the front, and the error then names a directive nobody wrote. It cost a green gate here when one word was added to a header paragraph and the line below reflowed:

```console
$ printf '#!/usr/bin/env bash\n# one two, shellcheck,\n# shfmt and nix\ntrue\n' >a.sh
$ printf '#!/usr/bin/env bash\n# shellcheck, shfmt and nix\ntrue\n' >b.sh
$ shellcheck a.sh; echo "a=$?"; shellcheck b.sh >/dev/null 2>&1; echo "b=$?"
a=0
b=1
```

`b.sh` answers `SC1073 (error): Couldn't parse this shellcheck directive` followed by `SC1072`, and both are errors rather than warnings, so the run stops there. A second space after the `#` does not save it. Keep the word away from the front of a comment line, or write it as `` `shellcheck` ``, which the same probe reports clean — and a backtick around a tool's name is what the comment rules ask for anyway

**Judge `grep` by what it says, not by its status.** A regex `grep` cannot compile is not a uniform failure: GNU and BSD `grep` exit 2, busybox's does not compile it until there is a line to match, and all of them complain on stderr once it does. A broken exclusion regex can leave the filtered log empty, making a later scan report no findings. Feed the probe a line of input rather than `/dev/null`, capture stderr, and treat a complaint as the answer

**An undefined `awk` escape is noise, not necessarily a difference.** `\ ` for a space is undefined by POSIX, but gawk, mawk, busybox awk, goawk and the one-true-awk macOS ships all read it as a space. Fix it for the warning, and do not invent a portability story that measurement does not support — the same discipline that keeps the bash floor honest in [portability.md](portability.md). **An `exit N` inside an `awk` program is awk's status, not the script's**, which is why `check-sh.sh` counts only bash-shaped ones — `exit N` followed by `;`, end of line, `&&` or `||` — and leaves `{ exit 1 }` alone

**`awk -v` runs escape processing over the value, so a regex passed that way loses its backslashes.** POSIX reads a `-v` value as if it stood between double quotes in the program, so `\t` turns into a tab in every awk measured, and `\.` — an escape POSIX leaves undefined — turns into a plain `.` in gawk, busybox awk and the one-true-awk macOS ships, while mawk keeps the backslash. Here the undefined escape of the entry above does change the answer:

```console
$ awk -v re='a\.b' 'BEGIN { print ("axb" ~ re) }'
awk: warning: escape sequence `\.' treated as plain `.'
1
$ RE='a\.b' awk 'BEGIN { print ("axb" ~ ENVIRON["RE"]) }'
0
```

The dot now matches any character, and the only trace is gawk's warning on stderr — the one-true-awk and busybox print none — so a suite that reads stdout alone sees a pattern that quietly matches too much. **Hand data to awk through the environment and read `ENVIRON["NAME"]`**: POSIX makes each element the variable's value as it is and the measured awks agree. A gate that runs awk over its own patterns can also require a clean run to leave stderr empty

## Next

The manuals and wiki pages behind each entry are in [sources.md](sources.md#pitfalls)
