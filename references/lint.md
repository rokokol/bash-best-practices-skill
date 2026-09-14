# Linters, and the one honest way past them

Two tools read every script in this family — shellcheck for what the shell will do with it, `shfmt` for what it looks like — and both are run from a pinned dev shell rather than from PATH's luck. This file rules on what to do with a finding, which is nearly always "rewrite", and on the few places where generated shell needs quoting the linter cannot check for you

## The order: `bash -n`, then shellcheck, then `shfmt`

- **`bash -n` runs first, on every file.** It parses without executing, so a missing `fi` is reported as a syntax error rather than as thirty shellcheck findings downstream of it, and a syntax-breaking mutation is classified as unusable instead of a defect the suite caught
- **A zsh file gets `zsh -n` and nothing else.** shellcheck has no zsh dialect and `shfmt` has no zsh parser; a completion under `share/zsh/site-functions/` is zsh, so the parse is the whole check it can have ([completions.md](completions.md))
- **A shebang-less file that is bash says so in its first line**: `# shellcheck shell=bash`. Bash completions are sourced, never executed, so they carry no shebang, and without the directive shellcheck either guesses `sh` and reddens every `[[` or refuses the file outright
- **`shfmt -d -i 2 -ci`, in that spelling.** `-d` prints a diff and exits non-zero instead of rewriting, which is what a gate wants — the rewrite is a thing a person does and reads. Two-space indent and `-ci` (case-indented arms) are what the family's scripts are already written in, and they are what makes the dispatcher and flag-parser shapes in [shape.md](shape.md) come out the way `check-sh.sh` parses them

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
