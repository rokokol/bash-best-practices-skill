# The help is the single source of truth

A CLI has one complete list of what it does, and it is what the tool prints when asked. Everything else — a table in a readme, the words a completion offers — is a mirror, allowed only where its reader cannot ask the tool, and only because a machine diffs it against the dispatcher in both directions. This file says how the help is produced, what it has to contain, and in what textual shape, because `check-sh.sh` reads it

## Three ways to print it, and when each applies

```sh
usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }
usage() { awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; }
```

- **The header, extracted open-endedly, for a checker or any small utility.** Both forms print lines 2 onward up to the first line that is not a comment, stripping one `#` and one optional space. The `sed` pair is the family's default (`check-skill.sh:22`, `obsi.sh:46-48`); `$d` drops the terminator line that the range `/^[^#]/` has to include in order to stop there. The `awk` one-liner does the same in one process without that trick (`check-changelog.sh:26`), and is the better read in a script that already parses text with awk. `check-sh.sh` recognises either, and then proves the extraction: the last line of `--help` must equal the last line of the header, or the finding is `--help stops before the end of its own header`
- **A quoted heredoc, when the help is longer than a header should be.** The rule that the header carries the whole story then weakens to this: the header carries the synopsis and the claims, the heredoc carries the list

```sh
help_run() {
  cat <<'EOF'
name.sh run [-n | --dry-run] [-l DIR]
...
EOF
}
```

- **The delimiter is quoted.** `<<'EOF'`, so `$1`, backticks and `${...}` in the examples stay literal — and shellcheck reads that cleanly, where a `printf` full of literal `${...}` needs a disable comment (SC2016, [lint.md](lint.md))
- **`help [SUB]`, when subcommands have flags of their own.** One `help_<sub>()` per subcommand, a `cmd_help` dispatching on the topic, and a general help that lists the subcommands and says where the rest is (`t.sh:1737` and `t.sh:1941`). `check-sh.sh` runs `"$BASH" "$SCRIPT" help SUB` for every `help_<sub>()` it finds, and checks that subcommand's flags against that text, so splitting the help costs nothing in coverage

**A fixed line range is forbidden, and `ci.sh:19` is the live proof.** It reads `usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }` while that header ends at line 16, so today `bash ci.sh --help | tail -n 1` prints `set -euo pipefail` — measured on 2026-09-11. The range drifts in both directions, and neither direction announces itself: one sentence more and the help cuts itself short, one sentence fewer and it prints code. `obsi.sh:44-45` states the rule in a comment where the temptation lives, and the finding is `usage() prints a fixed line range`, fired by the pattern `sed -n 'N,Mp' "${BASH_SOURCE` whatever the numbers are

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
- **Every environment variable the script reads, under a heading of its own** (`Environment:`, or `Runtime environment` for an installer listing what the *installed* tool reads, `install-sh.md:21`). They are found in the source by prefix — `grep -oE "(^|[^A-Za-z0-9_])${PREFIX}[A-Z0-9_]+"` — so a script with variables takes `-e PREFIX`, and a prefix that matches nothing is itself a finding rather than a silent pass
- **Every exit code the script can produce, in a sentence beginning `Exit` or as rows `  N  text`.** `Exit: 0 clean, 1 findings printed, 2 a usage error.` is the compact form (`check-changelog.sh:21`); a harness with a whole band lists them as rows under `help codes` (`t.sh:1924-1937`). The checker reads the numbers on the line carrying `Exit` and on the line after it, since a header wraps the sentence, and every `  N  ` row. The source side is a bash-shaped `exit N` with N greater than zero, outside comments and ending its statement — an awk program's `{ exit 1 }` inside a quoted string is not one, and a heredoc body is blanked first — and the finding is `exits N but its help never lists N`

## Flag grammar

- **A short flag always comes with a long one, and never alone.** Users type the short one and read the long one; a short-only flag is unreadable in a script, and a long-only flag is unbearable in a terminal. `-f` exists only where a `--force` exists (`install-sh.md:17`)
- **A boolean is a single flag that flips the default, not a `--x`/`--no-x` pair.** The installer is declarative — each run converges to exactly the flags given, so dropping a flag undoes it, the way unsetting a Nix option does on rebuild (`install-sh.md:19`). Say that in one sentence in the help, because it is a behaviour change for anyone expecting pairs
- **A value-taking flag guards explicitly**, `(($# >= 2)) || die "-l needs a directory"`, never `"${2:?value required by $1}"`, for the reason [shape.md](shape.md#exit-codes) gives; the huix-standard template used to prescribe the other form, and was changed rather than followed
- **An unknown flag prints the usage to stderr and exits 2**, and flags that cannot combine refuse each other by name — `--uninstall` takes no configuration, because an uninstall has no configuration (`install-sh.md:17`)
- **The fixed core comes first and in this order**: `-h, --help`, then `-v, --version` where the tool has a version, then the repo-specific flags (`install-sh.md:9-15`). The completions offer the same tokens, checked by `check-sh.sh -c` ([completions.md](completions.md))

## Mirrors live where the tool cannot be asked, and are diffed both ways

**A README table of subcommands is allowed, because its reader, on a hosting site, cannot run the tool, and because hand-written text can be better than generated text** — a sentence saying which question a subcommand answers is worth more than its flag list repeated. **A document an agent reads — SKILL.md, a reference page — does not restate the list**: the agent can run the help in one call, so a copy there is paid for in context on every load and is one more place to drift, and it sends the reader to the help instead (below). tests' SKILL.md carried such a table, and `t.sh help` printed the same nine one-line answers. A guide that routes tasks to commands, most of them another tool's, is not a mirror of the script at all and belongs to the check for that tool's interface, below. What is not allowed anywhere is an unchecked mirror: every document that names subcommands goes under `check-sh.sh -d DOC`, which reads it in both directions. Forward, every subcommand must appear in some line of the doc together with the tool's name as a whole word, which covers both a table cell like `` | `ci.sh log` | `` and a layout line; backward, every code span that opens with the tool's name — `` `NAME word` ``, `` `NAME sub --flag` `` — must name a subcommand the dispatcher has and flags that subcommand parses, up to a `--`. The findings are `DOC never names NAME SUB`, ``DOC names `NAME word`, which NAME does not have`` and ``DOC gives `NAME sub` the flag --x, which it does not parse``

**A document about somebody else's tool is a different check, and not this checker's.** There is no source to read a dispatcher from, so the truth is the tool's own advertised interface — its `help`, a schema, an MCP server's tool listing — and holding a document to that belongs to the [ci](https://github.com/rokokol/ci-skill) skill's checkers, beside the gate that ties a repository's documents to the packaged thing. `check-sh.sh` reads source, and a tool without source here is out of its reach on purpose

**`check-sh.sh --template` prints the canonical script, and `--template bash` and `--template zsh` its two completions.** They are the text the checker plants its defects into on every run, so the skeleton a new script starts from and the shape the checker proves itself on are one file, and [`templates/`](../templates/) in the skill's repository is held byte-equal to that output by its gate

**A skill that ships a script says so in SKILL.md, in one line: "the help is the reference: run `X help [SUB]` before an unfamiliar command".** The point is not politeness to the reader but instruction to the next agent — a command guessed from documentation is a command nobody checked, and the documentation is a mirror by construction. Such a document mentions a few subcommands and sends the reader to the help for the rest, so it goes under `check-sh.sh -m DOC` rather than `-d`: every mention is held to the dispatcher, and no list is demanded, since a redirect that named everything would be the second list it exists to avoid

This is the shell-CLI case of the rule the [ci](https://github.com/rokokol/ci-skill) skill states for every list CI consults, [one source of truth per list](https://github.com/rokokol/ci-skill/blob/HEAD/references/checks.md#one-source-of-truth-per-list): hand-written mirrors allowed only where the list cannot be asked for, drift-checked, in both directions. The tokens a completion must offer for the same flags are in [completions.md](completions.md)
