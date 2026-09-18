# Portability

What a script may assume about the machine it lands on, how that assumption is written into the file, and how it is proved rather than asserted. macOS ships `/bin/bash` 3.2.57 from 2007 and a BSD userland, so "it works here" is never the claim — the claim is one line in the header, and a checker and a CI job hold the file to it. The blocks below show the commands and their output under bash 5.3 and `bash:3.2`; the **Needs** column comes from bash's own [NEWS](https://tiswww.case.edu/php/chet/bash/NEWS), and the GNU-only rows rest on the primary man pages collected in [sources.md](sources.md#portability)

## Declaring the floor

**Every script says in its header which bash it needs.** An unstated floor is discovered only when the script lands on an older machine. The line is in the header comment, for the reason [shape.md](shape.md#the-header-and-the-help) gives

**A script that travels declares `Needs bash 3.2 and POSIX tools only`, and the line is two claims rather than one.** `check-sh.sh` reads `Needs bash X.Y` for any X.Y and holds the script to the constructs that arrived *after* that floor, so a tool declaring 4.3 is checked for 4.4 and 5.2 and left alone about `mapfile`; `POSIX tools only` is the second claim and turns on the userland half by itself, because bash 5 from brew with a BSD `sed` around it is still a macOS machine. A header that declares neither promises nothing and is checked for neither

**A tool outside that promise is named on the same line.** `Needs bash 3.2, git and POSIX tools only` is the shape, and `check-sh.sh` holds the claim to it: every command the script calls that is not a bash builtin, not one of its own functions and not a utility both a GNU and a BSD userland ship has to appear in the header. This is the half a macOS runner cannot prove — a bash is proven by running under it, where a missing tool is missing only on the machine that lacks it — so naming is what makes the claim readable rather than aspirational, and it costs one word. A claim covering only part of the script says which part: `POSIX tools only for its own code` is how `check-sh.sh` and `check.sh` carry that, one reading the script it is given through `shfmt` and `jq`, the other linting through tools its dev shell pins

**A tool that wants 4.0 or 5.2 declares that instead, and says why in one line.** A floor is a cost paid by every consumer, so the reason belongs beside it: `Needs bash 5.2 (a literal & in a ${s//p/r} replacement)` is a sentence a reviewer can argue with, while a bare `Needs bash 5.2` is one nobody can. A tool nobody ships to macOS is entitled to 5.2 — it is entitled to it out loud, and the checker then stops arguing about everything below it

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

`declare -A` is the worst of them: the array is an ordinary indexed one, every string key subscripts to 0, and a map of ten entries holds the tenth under all ten names without a word after the first line. `mapfile` leaves the list empty and every downstream loop runs zero times, so a 3.2 proof plants both failures

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

Escaping `&` as `\&` fixes the 5.2 interpretation and breaks 3.2 — `docker run --rm bash:3.2 bash -c 's="a<b"; echo "${s//</\&lt;}"'` prints `a\&lt;b` — so `\&` is not a portable fix, it is a declaration of a 5.2 floor. **The portable edit cuts around the occurrence instead**, which has neither problem and is identical on both: `bash -c 'c="a b c"; f="b"; rep="X&Y"; printf "%s\n" "${c%%"$f"*}$rep${c#*"$f"}"'` prints `a X&Y c` under 5.3 and under 3.2 alike

**A heredoc inside `$( )` or `<( )` is read as code by 3.2, and `bash -n` passes it.** Before 4.0 the parser finds the end of the substitution by scanning the heredoc's body, so an unpaired `)` there ends the substitution early and the value quietly takes in the rest, while an unpaired `'` is a syntax error. With `p.sh` holding `x="$(`, `cat <<'EOF'`, `a ) b`, `EOF`, `)"` and `printf "[%s]\n" "$x"` on six lines:

```console
$ docker run --rm -v "$PWD/p.sh:/p.sh:ro" bash:3.2 bash -n /p.sh; echo $?
0
$ docker run --rm -v "$PWD/p.sh:/p.sh:ro" bash:3.2 bash /p.sh
[a  b
EOF
)]
$ docker run --rm -v "$PWD/p.sh:/p.sh:ro" bash:4.0 bash /p.sh
[a ) b]
```

The idiom opens the substitution on the line before the heredoc, so no one-line pattern sees it: `check-sh.sh` tracks the open substitutions across lines instead. A heredoc in backticks, or one outside the substitution, reads correctly under 3.2, and a text of several lines needs neither: single quotes carry the newlines, with each `'` inside written `'"'"'`

## Construct → floor → what to write instead

| Construct | Needs | Write instead |
| --- | --- | --- |
| `declare -A`, `local -A` | bash 4.0 | two indexed arrays, or a `key<TAB>value` stream through `grep`/`awk` |
| `mapfile`, `readarray` | bash 4.0 | `while IFS= read -r l; do a+=("$l"); done < <(…)` |
| `${v^^}`, `${v,,}` | bash 4.0 | `tr '[:lower:]' '[:upper:]'` |
| `;;&` in a `case` | bash 4.0 | repeat the arm, or split the `case` |
| `cmd \|& cmd` | bash 4.0 | `cmd 2>&1 \| cmd` |
| `shopt -s globstar` | bash 4.0 | `find` with `-name`, results filtered rather than excluded |
| `read -t 0.5` (fractional) | bash 4.0 | whole seconds, or a deadline loop |
| a heredoc inside `$( )`, `<( )` or `>( )` | bash 4.0 | a single-quoted text, or the heredoc outside the substitution |
| `exec {fd}<file` | bash 4.1 | a fixed descriptor number |
| `[[ -v x ]]` | bash 4.2 | `[[ -n "${x-}" ]]` or `[[ -z "${x-}" ]]` — the same test |
| `${s:0:-1}` | bash 4.2 | `${s%?}` |
| `local -n`, `declare -n` | bash 4.3 | bash's dynamic scoping — a callee reads the caller's locals |
| `wait -n` | bash 4.3 | `wait` for the whole batch and read each job's status from a file |
| `${x@Q}` | bash 4.4 | `printf %q` |
| `${x//"$a"/"$b"}`, `&` in a replacement | 3.2 and 5.2 differ | `${x%%"$a"*}$b${x#*"$a"}` |
| `readlink -f` | GNU; macOS only from 12.3 | a `while [[ -L ]]` loop over plain `readlink` |
| `mktemp -p`, `--suffix`, `-t` | differ | `mktemp -d "${TMPDIR:-/tmp}/NAME.XXXXXX"` — an explicit template, see the correction below |
| `sed -i` with no argument | GNU | write to a temp file and `mv`; `sed -i ''` is the BSD spelling and fails on GNU |
| `grep -P`, `\b`, `--exclude-dir` | GNU | POSIX ERE and bracket expressions, and paths filtered out of the results rather than excluded |
| `date -d` | GNU | arithmetic; some BSD `date` rolls `02-30` into March |
| `sort -V` | GNU | compare identifier by identifier |
| `timeout` | GNU | a watchdog over a process group under `set -m` |
| `tar --wildcards`, `tar --null -T -` | GNU | bsdtar rejects both; the busybox tar a 3.2 container brings has neither |
| `nproc` | GNU | `nproc 2>/dev/null \|\| sysctl -n hw.ncpu 2>/dev/null \|\| echo 4` |
| `fold` counting characters | coreutils 9.8 | wrap in bash; older `fold` cuts UTF-8 by bytes and no locale fixes it |

**A bare `mktemp -d` works on BSD.** The macOS [mktemp(1)](https://man.freebsd.org/cgi/man.cgi?query=mktemp&sektion=1&manpath=macOS+14.8.5) page says "If no arguments are passed or if only the **-d** flag is passed **mktemp** behaves as if **-t tmp** was supplied". An explicit template still honours `TMPDIR` on both userlands and puts the owner's name in the path, which makes a leaked directory attributable. The flags differ: `--suffix` is GNU-only, BSD `-t` takes a *prefix* argument where GNU `-t` takes none and is deprecated, and `-p` means "the directory" on GNU but "the fallback for `-t` when TMPDIR is unset" on BSD, so `check-sh.sh` flags `mktemp -p`, `--tmpdir`, `--suffix` and `-t`, and never a bare `mktemp -d`

## The proxy is labelled, the proof is a run

**`check-sh.sh` greps a 3.2-claiming script for newer constructs, and the finding says it is a proxy.** The pattern is the table above turned into alternatives, every literal split by a bracket expression so the guard cannot match its own source line. A `]` in such a pattern goes *first* in its bracket expression, because `\]` is not an escape there and can terminate the bracket expression. It is worth running because it is instant and catches the constructs somebody thought to list. It is worth labelling because that set is not the set of things 3.2 rejects. Three rows of the table stay outside it, because a grep cannot tell the defect from the fix: `nproc`, whose portable spelling above is itself a `nproc` call with a fallback; `fold`, where the defect is the coreutils version, not the call; and `\b` in a `grep` pattern, which looks like any other backslash in a string

**A grep cannot enumerate the language.** Under a real 3.2, `|&` and `;;&` stop at syntax errors, `${x@Q}` and `${s:0:-1}` at expansion errors, and `exec {fd}<` at an exec that finds no command `{fd}`; `local -n`, `read -t 0.5`, `wait -n` and `globstar` only complain on stderr and let the script continue. A list that has to be extended every time bash gains a feature is incomplete between releases

**The proof is the script run by a real 3.2.** Two places do it, and a repository whose script declares 3.2 has one of them:

```sh
# on a macOS runner, from templates/github/workflows/macos.yml
/bin/bash ./check.sh behaviour     # not `env bash`, which finds whatever bash is first on PATH
# locally, before pushing
docker run --rm -v "$PWD":/w -w /w -e CHECK_BASH32=1 bash:3.2 bash ./check.sh behaviour
```

`env bash` resolves to whichever bash is first on `PATH`, and on a Mac with Homebrew's or nix's bash that is 5, which proves nothing about `/bin/bash` — so the gate is invoked by absolute path and runs every nested script under `"$BASH"`, and the proof holds wherever it runs. The GitHub `macos` images themselves carry only 3.2: their [software list](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) reads `Bash 3.2.57(1)-release`, produced by running `bash` from the image's own `PATH` in [SoftwareReport.Common.psm1](https://github.com/actions/runner-images/blob/main/images/macos/scripts/docs-gen/SoftwareReport.Common.psm1). The job first checks the claim it is about — `((BASH_VERSINFO[0] == 3))` and `! "$BASH" -c 'declare -A m'` — then plants a `declare -A` and a `mapfile` in copies that must fail there, so a green run means the interpreter was asked. The `bash:3.2` image proves the interpreter and nothing else: its `grep` and `tar` are busybox, which reject GNU options a BSD userland accepts and accept some a BSD one does not. **The workflow exists if and only if some script in the repository declares 3.2**: `macos.yml` is that assertion's badge, and a repository with nothing claiming 3.2 has nothing to prove and carries no file

## Probe the mechanism, never a proxy

**A feature-detection check measures the thing the code depends on, not something that usually agrees with it.** The worked example is the locale probe. `${#s}` counts bytes or characters depending on the locale bash actually got:

```console
$ LC_ALL=C bash -c 's=ä; echo ${#s}'
2
$ LC_ALL=C.UTF-8 bash -c 's=ä; echo ${#s}'
1
```

`printf 'ä' | wc -m` is not an equivalent probe: GNU coreutils follows the locale here, while uutils counts UTF-8 characters regardless, so `wc` can vouch for a locale bash never got. On this machine the proxy agrees, which is the point — agreement today is not evidence:

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

So the script sets a candidate locale and asks a child bash `s=ä; echo ${#s}`, keeping the first candidate that answers 1

## Data crosses platforms too

**Strip the CR before looking at a line, whenever the input may have been checked out on Windows.** A CRLF file makes every blank line a line of one character, and a pattern list read from such a file turns into a pattern that matches every line of a CRLF log, so a healthy run is reported as a lie with an arbitrary build line offered as the evidence:

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
