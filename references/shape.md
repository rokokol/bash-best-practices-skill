# The shape of a script

Every utility in this family is the same script with a different middle: the same header, the same `set` line, the same refusal helpers, the same dispatcher, the same exit codes. Because `check-sh.sh` parses several of these forms literally, the spellings below are the definition rather than a preference. The skeleton that assembles them lives once, in [`templates/script.sh`](../templates/script.sh); nothing here is a second copy of it

## The header is the help

```sh
#!/usr/bin/env bash
# One sentence saying what this is and what it is for.
#
#   name.sh [-n NAME] [-d DOC]... SCRIPT
#
#   -n NAME   what the docs call the script (default: its basename)
#
# Exit: 0 clean, 1 findings printed, 2 a usage error.
# Nothing here reaches the network. Needs bash 3.2 and POSIX tools only.
set -euo pipefail
```

- **The shebang is `#!/usr/bin/env bash`, never `sh`.** Everything below — `[[`, arrays, `PIPESTATUS`, `local` — is bash, and `sh` is dash on a Debian host, which has none of it. A script whose shebang says bash is judged as bash whatever shell the caller is typing in, which is what makes it safe under the agent's harness ([harness.md](harness.md))
- **The header runs from line 2 to the first line that is not a comment, and it is the text `--help` prints.** One body of text cannot fall behind itself. How the extraction is written, and what the help must contain, is [help.md](help.md)
- **Usage lines are indented three spaces, flag and exit-code rows two.** The indent is grammar rather than typography: `check-sh.sh` reads flag rows as `^  -` and exit-code rows as `^  [0-9]+  `
- **The header says whether the script touches the network, and which bash it needs.** "Nothing here reaches the network" is what makes a check safe to run on a pull request; `Needs bash 3.2 and POSIX tools only` is the portability claim, matched as `^# .*Needs bash 3\.2` and, once present, policed by a proxy grep and proved by a run under 3.2 ([portability.md](portability.md))

## `set -euo pipefail`, flag by flag

- **`-e`** stops at the first failing command — but not inside `if`, `while`, `&&`, `||`, or a function whose own result is tested, which is where most surprises live
- **`-u`** makes an unset variable an error, so a typo'd name is not silently empty. `${VAR:-}` where empty is legitimate, and `${T-}` rather than `[[ -v T ]]`, which bash gained only in 4.2
- **`-o pipefail`** makes a pipeline report the last non-zero status. Without it `false | true` succeeds, and so does `pytest | tail`
- **`${PIPESTATUS[0]}` is read on the line after the pipeline and nowhere later.** Any simple command resets it, an assignment included, so the whole array is copied in one command — `ps=("${PIPESTATUS[@]}")` — and read from the copy. zsh spells it `$pipestatus` and indexes from 1, so a line moved between the two silently yields an empty string ([harness.md](harness.md))
- **A `for` loop exits with its last iteration's status**, so a loop that fails in the middle and succeeds at the end succeeds: count failures in a variable and exit on the counter
- **`-e` is dropped only where findings are counted, and a comment above the line says so** — `# No -e: every finding is printed and counted, and a non-zero grep is data, not a failure`. A checker that must print every finding before exiting cannot die on the first non-zero `grep`. That is the only excuse, and it needs the comment because the reason is invisible in the line itself; anywhere else a missing `-e` is a script that carries on after a failure and exits 0
- **A producer whose consumer stops reading early dies of SIGPIPE, and `pipefail` makes that death the pipeline's status.** `yes | cmd` is the plain case; `awk '…{ exit }'`, `sed q` and `head` do the same to whatever feeds them, and under `set -e` the script ends there with 141 and not a word. Silencing the producer's stderr changes nothing, because the status is the signal and not the complaint. Say the death is expected with `{ yes || true; } | cmd`, let the consumer read on to the end, or feed it from a variable with `<<<`, which leaves no producer to kill:

```console
$ bash -c 'set -o pipefail; yes 2>/dev/null | head -1 >/dev/null; echo "status=$?"'
status=141
$ bash -c 'set -o pipefail; { yes || true; } | head -1 >/dev/null; echo "status=$?"'
status=0
$ bash -c 'set -euo pipefail; seq 200000 | awk "NR == 1 { exit }"; echo survived'; echo "exit=$?"
exit=141
$ bash -c 'set -euo pipefail; seq 200000 | awk "NR == 1 { print } { }" >/dev/null; echo survived'
survived
$ bash -c 'set -euo pipefail; v=$(seq 200000); awk "NR == 1 { exit }" <<<"$v"; echo survived'
survived
```

## Refusing

```sh
fail() {
  printf 'check-sh: %s\n' "$1" >&2
  exit 1
}
die() {
  printf 'check-sh: %s\n' "$1" >&2
  exit 2
}
```

- **`printf`, not `echo`.** `echo` is the least portable builtin there is: a message beginning with `-n`, or carrying a backslash, is interpreted rather than printed, and bash, zsh and `/bin/echo` disagree about which. Use `printf '%s\n'` everywhere
- **`die` inside `$(...)` exits the subshell, not the script.** A helper that can refuse assigns to a global and `return`s; it never hands its answer back through command substitution, where refusal can leave an empty result while the caller continues

## Finding itself, and its scratch space

```sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/check-sh.XXXXXX")
trap 'rm -rf "$work"' EXIT
```

- **The first line is the self-location.** `$0` is wrong under `source`, a bare `dirname` leaves a relative path that any later `cd` invalidates, and `--` survives a script whose path begins with a dash
- **The `readlink` loop is added only when the script is reached through a symlink** — an installed tool on `PATH` that reads data beside itself would otherwise look beside the link rather than the target. It is a loop over plain `readlink`, never `readlink -f`, which is GNU and reached macOS only in 12.3 ([portability.md](portability.md)). In a script nobody symlinks the loop is dead code the next reader has to disprove
- **Every temporary lives under one `mktemp -d` with a template that names the owner, cleaned by a single `trap … EXIT`.** A fixed path under `/tmp` collides between two runs and is a symlink attack in a shared directory; `"${TMPDIR:-/tmp}/NAME.XXXXXX"` makes the leftovers of a crashed run greppable. What the template does and does not buy on a BSD `mktemp` is in [portability.md](portability.md)
- **In a Nix dev shell, `export -n out err` goes right after the `set` line.** The build exports `$out`, and bash keeps that export on a local of the same name: once a local `out` grows past the environment limit, `exec` refuses subsequent commands with "Argument list too long". The script's own names are its own

## Streams, and the absence of decoration

- **Everything a human reads goes to stderr, everything a program parses to stdout.** Then `tool | jq` works while progress and refusals stay visible, and this is also why the help goes to stdout under `--help` and to stderr from a refusal arm
- **No colour, and therefore no `NO_COLOR`.** These scripts run under CI, under an agent's Bash tool and in pipes far more often than in a terminal, and doing colour honestly means an isatty test, a `NO_COLOR` check and a `--no-color` flag — three code paths carrying no information. Emitting none is one path
- **No `--json` flag either; a `status` subcommand prints one JSON line instead.** A flag that reshapes every output doubles every output path in the script and every row in the help, where a subcommand whose whole contract is machine-readable has one shape, is named in the dispatcher, and is checked like any other subcommand

## Exit codes

**0 clean, 1 the thing asked about is wrong, 2 asked wrongly or there was nothing to check** — and "nothing to check" is a refusal, never a quiet pass, because an extractor that finds nothing must not read as "no drift". The reason is a measurement rather than a taste: the survey of what common tools answer to an unknown flag is in [sources.md](sources.md#the-shape), and 2 is the only value with a plurality behind it

- **`"${2:?value required by $1}"` is not a usage guard** — it exits 1 with bash's own message, measured in [pitfalls.md](pitfalls.md#the-interpreter) — so the guard is `(($# >= 2)) || die "-n needs a name"`
- **A harness whose 1 belongs to the command it runs takes 64–89 instead.** It passes the child command's status through unchanged and puts its own verdicts in a band common test runners do not use: pytest occupies 2 to 5, GNU make 2 and cargo-nextest 4

## The verdict line

- **A finding is one line on stderr prefixed with the script's own name; a clean run ends `<name>: everything holds` on stdout.** The stable prefix makes a planted-defect proof possible: the altered copy must fail *for its own reason*, decided by matching that finding line

## The dispatcher

```sh
cmd="${1:-}"
(($# == 0)) || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  stop) cmd_stop "$@" ;;
  -h | --help | help) usage ;;
  '')
    usage >&2
    exit 2
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
```

- **`check-sh.sh` parses exactly this.** It takes the top-level block between `^case "$cmd" in$` and `^esac$`, reads each branch as `^  ([a-z][a-z0-9-]*)( \| …)*\)`, requires one arm spelled exactly `-h | --help | help)` so a reader and a completion can count on all three, takes `''` and `*` as the refusals, and holds every remaining name to the help, the docs and the completions. A heredoc body is blanked before any of this, so a help text or a template inside one is not read as the script's own code. A `case "$1"` inside a helper function is not a dispatcher and is skipped — and a `case "$1"` used *as* the dispatcher is not recognised at all, which is why `cmd="${1:-}"` is mandatory rather than stylistic. `(($# == 0)) || shift` sits before the `case` so `"$@"` in a branch is the subcommand's own arguments, and so an empty invocation reaches the `''` arm instead of shifting an empty stack under `-u`. **Both refusal arms send the help to stderr and exit 2**: a `usage` in the `*)` arm without `>&2` is a finding, and so is a dispatcher with no `-h | --help | help` arm, since a tool whose help cannot be reached has no single source of truth whatever its header claims. A wrapper is the one exception: its `*)` arm hands the word to the tool behind it and carries the comment `# pass-through` to say so, which opens the subcommand set — the help and the documents may then name that tool's commands, `help` may be one of them, and `-h | --help` are answered as flags before the dispatcher instead The arms are spelled over four lines each because that is what `shfmt -i 2 -ci` does to the one-line form ([lint.md](lint.md))

## The flag parser

```sh
cmd_run() {
  local dry="" logdir=""
  while (($#)); do
    case "$1" in
      -n | --dry-run)
        dry=1
        shift
        ;;
      -l | --logdir)
        (($# >= 2)) || die "-l needs a directory"
        logdir="$2"
        shift 2
        ;;
      -h | --help) help_run ;;
      -*)
        usage >&2
        exit 2
        ;;
      *) break ;;
    esac
  done
  : "${C_LOGDIR:=$logdir}"
}
```

- **`check-sh.sh` attributes flags by the function they sit in.** An awk pass brackets functions on `^[a-z_]+\(\) \{` and `^}` (a one-line `usage() { …; }` opens and closes on the same line and brackets nothing): flags inside `cmd_<sub>() {` — the subcommand's name with hyphens turned into underscores, so `bisect-probe` parses in `cmd_bisect_probe` — belong to that subcommand and are held to `help <sub>`, flags at top level are global and held to the general help, and flags in any other function are ignored. A parser hidden in a helper is a parser the checker cannot attribute, and it reads as an undocumented flag. Environment variables are found the same way, by their prefix (`C_LOGDIR` above), and a prefix that matches nothing is itself a finding
- **`-*)` refuses before `*) break`.** Otherwise an unknown flag falls through to the positional arm and is quietly taken as an argument — the one failure a flag parser has that no test notices. The grammar these flags must follow, and the rows they earn in the help, are in [help.md](help.md)
