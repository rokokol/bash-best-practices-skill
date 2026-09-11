# Portability

What a script may assume about the machine it lands on, how that assumption is written into the file, and how it is proved rather than asserted. macOS ships `/bin/bash` 3.2.57 from 2007 and a BSD userland, so "it works here" is never the claim — the claim is one line in the header, and a checker and a CI job hold the file to it. Every rule below is followed by the reason and by the evidence: a `path:line` in the repository it was paid for in, or a block showing the command and its output. Two interpreters were available while this was written, and both were measured: `bash 5.3` on the machine and `bash 3.2.57(1)-release` in the local `bash:3.2` image. The **Needs** column of the table is the one thing here taken from documentation rather than measurement — it comes from bash's own [CHANGES](https://tiswww.case.edu/php/chet/bash/NEWS); what was measured for every bash row is that 3.2 refuses the construct and 5.3 accepts it, and the GNU-only rows rest on the man pages and the `path:line` beside them

## Declaring the floor

**Every script says in its header which bash it needs.** A floor nobody wrote down is a floor discovered by a CI run on a machine none of the code was written on — that is how `[[ -v VAR ]]` and `mapfile` were found in a checker meant to travel (`versioning/check.sh:41-43`). The line is prose in the header, so it is also in the text `--help` prints ([shape.md](shape.md))

**A script that travels declares 3.2, with exactly the text `Needs bash 3.2 and POSIX tools only`.** The wording is fixed because it is matched, not read: `check-sh.sh` turns its proxy grep on when the header matches `^# .*Needs bash 3\.2`, and a script that words the claim differently is silently unguarded. Present in `obsidian-cli/obsi.sh:16` and `ci/references/checks.md:41`, absent from `versioning/check-changelog.sh`, which is the gap the cascade closes

**A tool that wants 4.0 or 5.2 declares that instead, and says why in one line.** A floor is a cost paid by every consumer, so the reason belongs beside it: `Needs bash 5.2 (a literal & in a ${s//p/r} replacement)` is a sentence a reviewer can argue with, while a bare `Needs bash 5.2` is one nobody can. A tool nobody ships to macOS is entitled to 5.2 — it is entitled to it out loud

## What bash 3.2 does not have

```console
$ docker run --rm bash:3.2 bash -c 'x=1; [[ -v x ]] && echo yes'
bash: -c: line 0: conditional binary operator expected
bash: -c: line 0: syntax error near `x'
$ docker run --rm bash:3.2 bash -c 'v=abc; echo ${v^^}'
bash: ${v^^}: bad substitution
```

**Six of the constructs below fail without stopping the script, which is why a grep for them was ever thought necessary.** A syntax error or a bad substitution is loud and immediate; an unknown *option* to a builtin is a message on stderr and a carry-on — `declare -A`, `mapfile`, `local -n`, `globstar`, `wait -n` and `read -t 0.5` all behave that way. The four whose carry-on is a wrong answer rather than a missing one:

```console
$ docker run --rm bash:3.2 bash -c 'declare -A m; m[k]=v; echo "m[k]=${m[k]} m[0]=${m[0]}"'
bash: line 0: declare: -A: invalid option
m[k]=v m[0]=v
$ docker run --rm bash:3.2 bash -c 'mapfile -t a < /etc/hosts; echo "count=${#a[@]}"'
bash: mapfile: command not found
count=0
$ docker run --rm bash:3.2 bash -c 'f() { local -n r=$1; echo "r=$r"; }; v=5; f v'
bash: line 0: local: -n: invalid option
r=
$ docker run --rm bash:3.2 bash -c 'shopt -s globstar; echo ok'
bash: line 0: shopt: globstar: invalid shell option name
ok
```

`declare -A` is the worst of them: the array is an ordinary indexed one, every string key subscripts to 0, and a map of ten entries holds the tenth under all ten names without a word after the first line. `mapfile` leaves the list empty and every downstream loop runs zero times — the exact regression planted in `tests/check.sh:1648-1651` to prove the 3.2 job can fail

**Two substitutions behave differently rather than failing, which no grep can see at all.** In 3.2 a quoted replacement keeps its quotes as literal text, and from 5.2 an unquoted `&` in a replacement means the matched text:

```console
$ docker run --rm bash:3.2 bash -c 'c="a b c"; f="b"; r="X"; echo "${c//"$f"/"$r"}"'
a "X" c
$ bash -c 'c="a b c"; f="b"; r="X"; echo "${c//"$f"/"$r"}"'
a X c
$ bash -c 's="a<b"; echo "${s//</&lt;}"'
a<lt;b
$ docker run --rm bash:3.2 bash -c 's="a<b"; echo "${s//</&lt;}"'
a&lt;b
```

The first cost every `falsify` mutant on macOS: the edit written was `"if false"` with the quotes, nothing built, and the whole run reported `unusable` (`tests/CHANGELOG.md:31`). Escaping as `\&` fixes the second and breaks 3.2 — `docker run --rm bash:3.2 bash -c 's="a<b"; echo "${s//</\&lt;}"'` prints `a\&lt;b` — so `\&` is not a portable fix, it is a declaration of a 5.2 floor. **The portable edit cuts around the occurrence instead**, which has neither problem and is identical on both: `bash -c 'c="a b c"; f="b"; rep="X&Y"; printf "%s\n" "${c%%"$f"*}$rep${c#*"$f"}"'` prints `a X&Y c` under 5.3 and under 3.2 alike (`tests/t.sh:1362-1366`)

## Construct → floor → what to write instead

| Construct | Needs | Write instead |
| --- | --- | --- |
| `declare -A`, `local -A` | bash 4.0 | two indexed arrays, or a `key<TAB>value` stream through `grep`/`awk` |
| `mapfile`, `readarray` | bash 4.0 | `while IFS= read -r l; do a+=("$l"); done < <(…)` (`versioning/check-changelog.sh:149-155`) |
| `${v^^}`, `${v,,}` | bash 4.0 | `tr '[:lower:]' '[:upper:]'` |
| `;;&` in a `case` | bash 4.0 | repeat the arm, or split the `case` |
| `cmd \|& cmd` | bash 4.0 | `cmd 2>&1 \| cmd` |
| `shopt -s globstar` | bash 4.0 | `find` with `-name`, results filtered rather than excluded |
| `read -t 0.5` (fractional) | bash 4.0 | whole seconds, or a deadline loop |
| `exec {fd}<file` | bash 4.1 | a fixed descriptor number |
| `[[ -v x ]]` | bash 4.2 | `[[ -n "${x-}" ]]` or `[[ -z "${x-}" ]]` — the same test (`tests/t.sh:107-109`) |
| `${s:0:-1}` | bash 4.2 | `${s%?}` |
| `local -n`, `declare -n` | bash 4.3 | bash's dynamic scoping — a callee reads the caller's locals (`tests/t.sh:977-978`) |
| `wait -n` | bash 4.3 | `wait` for the whole batch and read each job's status from a file |
| `${x@Q}` | bash 4.4 | `printf %q` |
| `${x//"$a"/"$b"}`, `&` in a replacement | 3.2 and 5.2 differ | `${x%%"$a"*}$b${x#*"$a"}` |
| `readlink -f` | GNU; macOS only from 12.3 | a `while [[ -L ]]` loop over plain `readlink` (`tests/t.sh:27-40`) |
| `mktemp -p`, `--suffix`, `-t` | differ | `mktemp -d "${TMPDIR:-/tmp}/NAME.XXXXXX"` — an explicit template, see the correction below |
| `sed -i` with no argument | GNU | write to a temp file and `mv`; `sed -i ''` is the BSD spelling and fails on GNU |
| `grep -P`, `\b`, `--exclude-dir` | GNU | POSIX ERE and bracket expressions, and paths filtered out of the results rather than excluded (`tests/t.sh:738-742`) |
| `date -d` | GNU | arithmetic; some BSD `date` rolls `02-30` into March (`versioning/check-changelog.sh:130-131`) |
| `sort -V` | GNU | compare identifier by identifier (`versioning/check-changelog.sh:80-82`) |
| `timeout` | GNU | a watchdog over a process group under `set -m` (`tests/t.sh:974-976`) |
| `tar --wildcards`, `tar --null -T -` | GNU | bsdtar rejects both; the busybox tar a 3.2 container brings has neither (papers `306dbee`, `tests/check.sh:1242-1243`) |
| `nproc` | GNU | `nproc 2>/dev/null \|\| sysctl -n hw.ncpu 2>/dev/null \|\| echo 4` (`tests/check.sh:1396-1399`) |
| `fold` counting characters | coreutils 9.8 | wrap in bash; older `fold` cuts UTF-8 by bytes and no locale fixes it |

**Correction: a bare `mktemp -d` is not a BSD trap.** The macOS [mktemp(1)](https://man.freebsd.org/cgi/man.cgi?query=mktemp&sektion=1&manpath=macOS+14.8.5) page says "If no arguments are passed or if only the **-d** flag is passed **mktemp** behaves as if **-t tmp** was supplied", so the comment at `tests/check.sh:47` — "with a template, because the BSD mktemp on macOS wants one" — is a wrong recall, and the rule it justifies survives on two reasons that do hold: an explicit template honours `TMPDIR` on both userlands and puts the owner's name in the path, which is what makes a leaked directory attributable. What really differs is the flags around it — `--suffix` is GNU-only, BSD `-t` takes a *prefix* argument where GNU `-t` takes none and is deprecated, and `-p` means "the directory" on GNU but "the fallback for `-t` when TMPDIR is unset" on BSD — so `check-sh.sh` flags `mktemp -p`, `--tmpdir`, `--suffix` and `-t`, and never a bare `mktemp -d`

## The proxy is labelled, the proof is a run

**`check-sh.sh` greps a 3.2-claiming script for newer constructs, and the finding says it is a proxy.** The pattern is the table above turned into alternatives, every literal split by a bracket expression so the guard cannot match its own source line — a guard that reddens the commit introducing it gets deleted rather than fixed (`versioning/check.sh:44-50`). A `]` in such a pattern goes *first* in its bracket expression, because `\]` is not an escape there and GNU grep 3.12 read the escaped form as the bracket's end (`tests/check.sh:1205-1207`; not re-measurable here, where `grep` is ugrep 7.8.4 rather than GNU grep). It is worth running because it is instant and catches the constructs somebody thought to list. It is worth labelling because that set is not the set of things 3.2 rejects

**A grep let nine constructs through on its first audit**, which is the whole argument: `local -n`, `|&`, `;;&`, `${x@Q}`, `exec {fd}<`, `read -t 0.5`, `wait -n`, `${s:0:-1}`, `globstar` (`tests/CHANGELOG.md:50`). All nine were re-measured here under the real 3.2 and all nine are refused, but not alike: five stop the shell (`|&` and `;;&` as syntax errors, `${x@Q}` and `${s:0:-1}` as expansion errors, `exec {fd}<` as an exec that finds no command `{fd}`), and four — `local -n`, `read -t 0.5`, `wait -n`, `globstar` — are a complaint on stderr the script runs straight past. A list that has to be extended every time bash gains a feature is a list that is wrong between releases

**The proof is the script run by a real 3.2.** Two places do it, and a repository whose script declares 3.2 has one of them:

```sh
# on a macOS runner, from templates/github/workflows/macos.yml
/bin/bash ./check.sh behaviour     # not `env bash`, which finds Homebrew's 5
# locally, before pushing
docker run --rm -v "$PWD":/w -w /w -e CHECK_BASH32=1 bash:3.2 bash ./check.sh behaviour
```

`env bash` on a macOS runner resolves to Homebrew's bash 5 and proves nothing about `/bin/bash`, which is why the gate is invoked by absolute path and runs every nested script under `"$BASH"` (`tests/check.sh:42-48`). The job first checks the claim it is about — `((BASH_VERSINFO[0] == 3))` and `! "$BASH" -c 'declare -A m'` — then plants a `declare -A` and a `mapfile` in copies that must fail there, so a green run means the interpreter was asked (`tests/check.sh:1640-1652`). The `bash:3.2` image proves the interpreter and nothing else: its `grep` and `tar` are busybox, which reject GNU options a BSD userland accepts and accept some a BSD one does not. **The workflow exists if and only if some script in the repository declares 3.2** — one badge per assertion is the [ci](https://github.com/rokokol/ci-skill) skill's rule, `macos.yml` is that assertion's badge, and a repository with nothing claiming 3.2 has nothing to prove and carries no file

## Probe the mechanism, never a proxy

**A feature-detection check measures the thing the code depends on, not something that usually agrees with it** (`ci/references/checks.md:12`). The worked example is the locale probe. `${#s}` counts bytes or characters depending on the locale bash actually got:

```console
$ LC_ALL=C bash -c 's=ä; echo ${#s}'
2
$ LC_ALL=C.UTF-8 bash -c 's=ä; echo ${#s}'
1
```

The first version of the probe asked `printf 'ä' | wc -m` instead, because `wc` was the nearest thing to hand. It held until Ubuntu swapped coreutils for uutils, whose `wc` counts UTF-8 characters whatever the locale says, and the proxy started vouching for a locale bash never got. On this machine the proxy agrees, which is the point — a proxy that agrees today is not evidence:

```console
$ LC_ALL=C sh -c "printf 'ä' | wc -m"     # wc (GNU coreutils) 9.11 — the proxy agrees, today
2
```

**The probe must also be a child, because a rejected locale is still exported.** bash keeps its old locale when `setlocale` refuses a name, and passes the refused value to everything it starts:

```console
$ LC_ALL=xx_YY.UTF-8 bash -c 's=ä; echo "len=${#s} LC_ALL=$LC_ALL"'
bash: warning: setlocale: LC_ALL: cannot change locale (xx_YY.UTF-8): No such file or directory
len=2 LC_ALL=xx_YY.UTF-8
```

So the script sets a candidate locale and asks a child bash `s=ä; echo ${#s}`, keeping the first candidate that answers 1 (`rofi-wooordhunt/CLAUDE.md:36-38`)

## Data crosses platforms too

**Strip the CR before looking at a line, whenever the input may have been checked out on Windows.** A CRLF file makes every blank line a line of one character, and a pattern list read from such a file turns into a pattern that matches every line of a CRLF log — so a healthy run is reported as a lie, with a random build line offered as the evidence (`tests/t.sh:75-82`, found on a Windows runner, MolvAI 2026-09-05):

```console
$ printf 'alpha\r\n\r\nbeta\r\n' > crlf.txt
$ while IFS= read -r l; do printf '[%s] len=%s\n' "$l" "${#l}"; done < crlf.txt
[alpha] len=6
[] len=1
[beta] len=5
```

The read loop is `while IFS= read -r line || [[ -n "$line" ]]` with `line="${line%$'\r'}"` as its first statement, which also rescues a last line with no newline. A repository ever checked out on Windows carries `.gitattributes` with `* text eol=lf` as well, so git stops doing the conversion; the strip stays anyway, because the file may arrive from somewhere git never touched

## Next

Every manual, NEWS entry and man page behind the table is listed in [sources.md](sources.md#portability); the traps that are not about the machine at all are in [pitfalls.md](pitfalls.md)
