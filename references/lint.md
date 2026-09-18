# Linters, and the one honest way past them

Two tools read every script in this family — shellcheck for what the shell will do with it, `shfmt` for what it looks like — and both are run from a pinned dev shell rather than from PATH's luck. This file rules on what to do with a finding, which is nearly always "rewrite", and on the few places where generated shell needs quoting the linter cannot check for you

## The order: `bash -n`, then shellcheck, then `shfmt`

- **`bash -n` runs first, on every file.** It parses without executing, so a missing `fi` is reported as a syntax error rather than as thirty shellcheck findings downstream of it, and a syntax-breaking mutation is classified as unusable instead of a defect the suite caught
- **A zsh file is parse-checked by zsh and formatted by `shfmt -ln zsh`.** shellcheck has no zsh dialect, so a completion under `share/zsh/site-functions/` gets `zsh -n` rather than a lint; `shfmt` does read the dialect, since 3.13.0, so the format half is held to the same spelling as the bash files. That dialect is young, so a `shfmt` bump can redden a zsh file on formatting alone — read the diff, do not drop the check ([completions.md](completions.md))
- **A shebang-less file that is bash says so in its first line**: `# shellcheck shell=bash`. Bash completions are sourced, never executed, so they carry no shebang, and without the directive shellcheck either guesses `sh` and reddens every `[[` or refuses the file outright
- **`shfmt -d -i 2 -ci`, in that spelling, plus `-ln zsh` for the zsh files.** `-d` prints a diff and exits non-zero instead of rewriting, which is what a gate wants — the rewrite is a thing a person does and reads. Two-space indent and `-ci` (case-indented arms) are what the family's scripts are already written in, and they are what makes the dispatcher and flag-parser shapes in [shape.md](shape.md) come out the way `check-sh.sh` parses them. A bash file needs no `-ln`, since `auto` reads the shebang; a `#compdef` file has none to read, so its dialect is named

## Reading a script rather than scanning it

A tool that decides something about shell source — a checker, a generator, a migration — reads the text or it reads the grammar, and the two are not the same tool with a different spelling. `<<` opens a heredoc everywhere except inside `$(( ))`, where it shifts ([pitfalls.md](pitfalls.md#the-interpreter)); a `case "$cmd" in` inside a heredoc is a string; `declare -A` in a message is prose. Each of those needs a scanner to track quotes, comments and arithmetic across lines, and what it costs is not the code — it is that the failure is silent, because a scan that has swallowed the rest of a file reports nothing wrong about it

`shfmt --to-json` prints mvdan.cc/sh's whole syntax tree with a line number on every node, which answers all of it by construction. Flatten it once into rows a rule can read with awk and the non-POSIX dependency lives in that one stage; `check-sh.sh` beside this file is that shape, and its `read_tree` is fifteen lines

What is not obvious from the outside, and costs a measurement each to find out:

- **`--to-json` reads stdin only**, and `--filename NAME` is what lets `-ln auto` guess the dialect from a name it never opens
- **A redirection carries no `Type`**, so it cannot be found by one; `OpPos` marks it, and every other node carrying `OpPos` — `BinaryCmd`, `BinaryArithm`, `UnaryTest` — does have a `Type`. Its `Hdoc` key is **absent** rather than null unless it opens a heredoc, so testing for the key finds only heredocs
- **`declare`, `local`, `typeset`, `export` and `readonly` are a `DeclClause`**, not a call, and a flag there is an `Assign` with no `Name`. That is what makes `declare -rA` and `local -Ar` answerable at all
- **Comments hang off the statement they precede**, not off the file, and are marked by `Hash`, the position of the `#`
- **A `ParamExp` keeps its operator in `Exp.Op`**, but a slice and a replacement have none: they carry `Slice` and `Repl` instead, and `${x@Q}`'s letter is the `Exp`'s own word
- **A `CallExpr` keeps `Assigns` beside `Args`**, so `v=$(…)` is a call with no arguments at all and a descent into `Args` alone loses every assignment and the substitutions inside it
- **Backticks are a `CmdSubst` too**, told apart by a `Backquotes` key that is absent on `$( )` — which matters because bash 3.2 mishandles a heredoc in the second and not in the first
- **jq binds before it pipes**: `.Name.Value` and `.Backquotes` are gone inside `.Body` or `.Stmts`, so they are bound to a variable first

**The JSON has moved once, so check the shape rather than the version.** 3.13.1 wrote `"Op": 71` where 3.14.1 writes `"Op": "<<"`. A version number is a proxy for what a rule downstream depends on; a small probe exercising every kind of row, flattened and compared to the table it must produce, is the thing itself, and it says which way the shape moved rather than scattering findings

**The alternative, where a new tool is not wanted, is `bash --pretty-print`**, which parses without executing and normalises quoting. It costs the line numbers, the comments, and any documentation: it is absent from the 5.0 and 5.1 man pages and the GNU manual, and appears only in `bash --help`

## Never silence a linter where a rewrite satisfies it

A `# shellcheck disable=` comment is a last resort for a rule that is wrong about this code, never a way past a rule that is right. The four that come up, each with its rewrite:

- **SC2251 — `! cmd` under `set -e` skips errexit.** The `!` makes the command a tested condition, so a failure no longer stops the script, and the negated status is usually discarded anyway. Write the intent: `if cmd; then exit 1; fi`
- **SC2016 — literal `${...}` in single quotes does not expand.** In a script that *generates* another script, not expanding is exactly the point, so write the generation as a heredoc with its `\$` escaped — shellcheck reads that cleanly, where a `printf` full of literal `${...}` needs a disable comment
- **SC2100 — `i=i+1` assigns the string.** If arithmetic was meant, `i=$((i + 1))`; if the literal text was meant, quoting says so — `i="i+1"`. Either way the ambiguity the warning is about is gone from the source
- **SC2207 — `files=($(cmd))` splits on `IFS` and then globs the pieces.** shellcheck suggests `mapfile`, which bash gained in 4.0 and macOS does not have, so the rewrite is the read loop, which satisfies the linter and the 3.2 floor at once ([portability.md](portability.md)):

  ```sh
  files=()
  while IFS= read -r line; do files+=("$line"); done < <(cmd)
  ```

- **A `disable=` that does survive carries its reason on the same line**, `# shellcheck disable=SC2016 # the ${} are literal, this text becomes the wrapper`. A bare code is an assertion with no argument behind it, and the next reader cannot tell a considered exception from a silenced one
- **Two things shellcheck reads that look like prose and a pattern.** A comment whose first word is `shellcheck` is a directive, so `# shellcheck and shfmt from the flake's dev shell` produces SC1073 "Couldn't parse this shellcheck directive" and such a comment must lead with another word. A `${` inside a single-quoted regex's bracket expression reads as an expansion, SC2016, where no expansion was meant; the rewrite puts `$` after `{`, `[^-A-Za-z0-9_{$]`

## The formatter's opinion is versioned, and the bump is a commit

**When the formatter's opinion changes between versions, the lock bump and the reformat land as one commit.** shfmt 3.14 writes `((! x))` where 3.13 wrote `((!x))`, and each version rejects the other's spelling, so a bump without the reformat, or a reformat without the bump, leaves the dependency update red over nothing the repository did. Split across two commits it is also unbisectable: every commit between them fails the gate for a reason unrelated to its own change

## One list of what gets linted

**The list of linted files lives once, in the gate's own `scripts=(…)`, and CI runs the gate rather than repeating the list.** A second copy drifts and lies about what was checked. Bash completions join it for shellcheck and `shfmt`; zsh ones go to a `zsh -n` loop beside it; and `check-sh.sh` is called from the same place, so a script cannot be linted without also being held to its own help

## Shell that writes shell

- **Every value pasted into a generated script goes through `sq`**, and it is not tidiness: the value and the path are executed by whatever runs the generated file, so pasted bare, a value holding a `"`, a `$(…)` or a backtick becomes code in it. Single quotes are the one sh quoting with no expansion inside, so escaping the single quote itself is the whole job, and the result is checked against a value carrying all three and a prefix with a space in it
- **A script that declares the 3.2 floor writes `sq` with `sed`, not with `${1//\'/\'\\\'\'}`.** The parameter-expansion spelling is correct on bash 4 and later, and broken on 3.2, which keeps the quoting characters of the replacement literally: `sq "a'b"` gives `'a'\''b'` on bash 5.3.15 and `'a\'\\'\'b'` under `docker run --rm bash:3.2`, which does not round-trip — `eval` on it dies with "unexpected EOF while looking for matching `'`", so the generated wrapper would be a syntax error rather than a mis-escaped string. Measured on this machine on 2026-09-11. The form that gives `'a'\''b'` on both is `sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }`
- **Every replacement spliced into a `sed` command is escaped first**, `sed 's/[&|\\]/\\&/g'`: an unescaped `&` in the replacement expands to the whole match, and a path containing the delimiter ends the expression. The same class of bug as `sq`, in the tool that renders configs rather than scripts

The version floors behind the rewrites above are in [portability.md](portability.md); the linter rules themselves are cited in [sources.md](sources.md#lint)
