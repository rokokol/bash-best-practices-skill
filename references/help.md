# The help is the single source of truth

A CLI has one complete list of what it does, and it is what the tool prints when asked. A copy of it lives only in a README, for a reader who has not installed the tool, and only because a machine diffs it against the dispatcher in both directions; the words a completion offers are held to the code the same way, by their own rule ([completions.md](completions.md)). This file says how the help is produced, what it has to contain, and in what textual shape, because `check-sh.sh` reads it

## One way to print it: a heredoc

```sh
usage() {
  cat <<'EOF'
name.sh — one line saying what it is

  name.sh run [-n | --dry-run] [-l DIR]   do the thing
...
EOF
}
```

- **The help is a quoted heredoc in `usage()`, right after the header and the `set` line.** It is code bash has already parsed, so it prints whatever the script was read from — a file, stdin, or the pipe `bash <(curl …)` hands it — and it is still the first thing a reader of the file meets
- **The delimiter is quoted.** `<<'EOF'`, so `$1`, backticks and `${...}` in the examples stay literal — and shellcheck reads that cleanly, where a `printf` full of literal `${...}` needs a disable comment (SC2016, [lint.md](lint.md))
- **`help [SUB]`, when subcommands have flags of their own.** One `help_<sub>()` per subcommand, each a heredoc of the same shape, a `cmd_help` dispatching on the topic, and a general help that lists the subcommands and says where the rest is. `check-sh.sh` runs `"$BASH" "$SCRIPT" help SUB` for every `help_<sub>()` it finds, and checks that subcommand's flags against that text, so splitting the help costs nothing in coverage

**The help never reads the script's own file.** Printing the header back out with `sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}"`, or the same in awk, reads the pipe bash itself is reading when the script arrives through `bash <(…)`, and bash has read it up to the command being run: called from the dispatcher at the bottom, the reader finds nothing left and the help comes out empty at exit 0, and called earlier it takes the rest of the program ([pitfalls.md](pitfalls.md#the-interpreter)). `check-sh.sh` runs the help a second time through `bash <(cat SCRIPT)` and reports a run that exits 0 with other text than the file's as `prints other text through a pipe than from the file`, naming the line when a `sed`, `awk`, `head`, `tail`, `cat`, `grep` or `cut` reads `"${BASH_SOURCE[0]}"` there. The probe decides and the grep only points, since `$0` names the file too and in awk is the record, which no grep can tell apart. A run that fails outright is a script that needs the files beside it, an installer most often: it says so and is no finding

**The header comment lists nothing.** It holds what an editor needs and the help what a caller needs, as [shape.md](shape.md#the-header-and-the-help) sets out. A usage, flag or code row in the header, or an `Exit` or `Environment:` line, is a second list beside the help, and the checker reports it as `carries a line that belongs to the help alone`. The drift is measured rather than feared: a header in the tests skill that listed `t.sh`'s subcommands beside its help fell three of them behind the dispatcher before anyone noticed

## What the help must list, and in what shape

The shape is grammar: these are the lines `check-sh.sh` parses, and a row spelled differently is a row the checker cannot see

```
name.sh — one sentence saying what this is

  name.sh run [-n | --dry-run] [-l DIR]   do the thing
  name.sh stop                            stop doing it
  name.sh status                          one JSON line, the machine-readable answer

Flags of name.sh run:

  -n, --dry-run       say what would happen, change nothing
  -l, --logdir DIR    where the logs go (default: $C_LOGDIR, else ./logs)

Environment:

  C_LOGDIR            default for --logdir

Exit: 0 clean, 1 findings printed, 2 a usage error.
```

- **Every subcommand, written at least once as `NAME sub`** — the tool's own name, a space, the subcommand — anywhere in the text. Missing one gives `dispatches 'SUB' but its help never mentions 'NAME SUB'`; the reverse gives `help lists 'NAME SUB', which the dispatcher does not have`
- **Every flag, as a row indented two spaces**: `  -x, --long VALUE  text`, short first, long second, the value name in capitals where the flag takes one, then two spaces and the prose. Only lines matching `^  -` are read as flag rows, so a flag mentioned only in a sentence is undocumented as far as the checker is concerned — `NAME SUB accepts FLAG but its help never mentions it`, or `help has a row for FLAG, which no parser accepts`
- **Every environment variable the script reads, under a heading of its own** — `Environment:`, or `Runtime environment` for an installer listing what the *installed* tool reads. They are found in the source by prefix — `grep -oE "(^|[^A-Za-z0-9_])${PREFIX}[A-Z0-9_]+"` — so a script with variables takes `-e PREFIX`, and a prefix that matches nothing is itself a finding rather than a silent pass
- **Every exit code the script can produce, in a sentence beginning `Exit` or as rows `  N  text`.** `Exit: 0 clean, 1 findings printed, 2 a usage error.` is the compact form; a harness with a whole band lists them as rows under `help codes`. The checker reads the numbers on the line carrying `Exit` and on the line after it, since a long sentence wraps, and every `  N  ` row. The source side is a bash-shaped `exit N` with N greater than zero, outside comments and ending its statement — an awk program's `{ exit 1 }` inside a quoted string is not one, and a heredoc body is blanked first — and the finding is `exits N but its help never lists N`

## Flag grammar

- **A short flag always comes with a long one, and never alone.** Users type the short one and read the long one; a short-only flag is unreadable in a script, and a long-only flag is unbearable in a terminal. `-f` exists only where a `--force` exists
- **A boolean is a single flag that flips the default, not a `--x`/`--no-x` pair.** In a declarative command each run converges to exactly the flags given, so dropping a flag undoes it. Say that in one sentence in the help, because it is a behaviour change for anyone expecting pairs
- **A value-taking flag guards explicitly**, `(($# >= 2)) || die "-l needs a directory"`, never `"${2:?value required by $1}"`, for the reason [shape.md](shape.md#exit-codes) gives
- **An unknown flag prints the usage to stderr and exits 2**, and flags that cannot combine refuse each other by name — `--uninstall` takes no configuration, because an uninstall has no configuration
- **The fixed core comes first and in this order**: `-h, --help`, then `-v, --version` where the tool has a version, then the repo-specific flags. The completions offer the same tokens, checked by `check-sh.sh -c` ([completions.md](completions.md))

## Mirrors live where the tool cannot be asked, and are diffed both ways

**A README table of subcommands is allowed, because its reader, on a hosting site, cannot run the tool, and because hand-written text can be better than generated text** — a sentence saying which question a subcommand answers is worth more than its flag list repeated. **A document an agent reads — SKILL.md, a reference page — does not restate the list**: the agent can run the help in one call, so a copy there is paid for in context on every load and is one more place to drift, and it sends the reader to the help instead (below). A guide that routes tasks to commands, most of them another tool's, is not a mirror of the script at all and belongs to the check for that tool's interface, below. What is not allowed anywhere is an unchecked mirror: every document that names subcommands goes under `check-sh.sh -d DOC`, which reads it in both directions. Forward, every subcommand must appear in some line of the doc together with the tool's name as a whole word, which covers both a table cell like `` | `tool.sh log` | `` and a layout line; backward, every code span that opens with the tool's name — `` `NAME word` ``, `` `NAME sub --flag` `` — must name a subcommand the dispatcher has and flags that subcommand parses, up to a `--`. The findings are `DOC never names NAME SUB`, ``DOC names `NAME word`, which NAME does not have`` and ``DOC gives `NAME sub` the flag --x, which it does not parse``

**A document about somebody else's tool is outside this checker's reach.** There is no local source to read a dispatcher from, so its advertised interface — its `help`, schema or tool listing — is the truth to check against; `check-sh.sh` reads shell source and refuses to guess beyond it

**`check-sh.sh --template` prints the canonical script, and `--template bash` and `--template zsh` its two completions.** They are the text the checker plants its defects into on every run, so the skeleton a new script starts from and the shape the checker proves itself on are one file, and [`templates/`](../templates/) in the skill's repository is held byte-equal to that output by its gate

**A skill that ships a script says so in SKILL.md, in one line: "the help is the reference: run `X help [SUB]` before an unfamiliar command".** The point is not politeness to the reader but instruction to the next agent — a command guessed from documentation is a command nobody checked, and the documentation is a mirror by construction. Such a document mentions a few subcommands and sends the reader to the help for the rest, so it goes under `check-sh.sh -m DOC` rather than `-d`: every mention is held to the dispatcher, and no list is demanded, since a redirect that named everything would be the second list it exists to avoid

The tokens a completion must offer for the same flags are in [completions.md](completions.md)
