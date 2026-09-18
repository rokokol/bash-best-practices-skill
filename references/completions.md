# Completions

A completion is the third reader of a CLI, and the only one that answers while the command is still being typed. A tool earns a pair when a person types it by hand more than once, which in practice means a tool on PATH, invoked by its own name. A script reached only by path, a gate or an agent gets none: its completion would be a list nobody presses TAB against and therefore a list nobody would notice going stale

## Two files, and where they go

A tool named `<cmd>` ships exactly two, and both names are load-bearing:

```
completions/<cmd>.bash   →  <prefix>/share/bash-completion/completions/<cmd>
completions/_<cmd>       →  <prefix>/share/zsh/site-functions/_<cmd>
```

bash-completion loads a file lazily by the command's name, and zsh searches `$fpath` for a file whose first line binds it to the command, so each is found by name with no line of user configuration anywhere — on NixOS `/etc/zshrc` walks `$NIX_PROFILES` and adds every profile's `site-functions` to `$fpath`, which is why installing the file is the whole job. The `.bash` extension exists only inside the repository, as the dialect marker shellcheck and shfmt read off the filename; installation drops it

An installer's own pair is the exception, because an installer is run out of a checkout and never installed: `completions/install.sh.bash` and `completions/install.sh.zsh` are sourced from the checkout instead, and the two `source` lines are what the README's "Any other distribution" section shows

## The bash file

- **Builtins only, and no dependency on the bash-completion package.** `complete`, `compgen` and `compopt` are builtins; anything else the file calls is a process spawned on every TAB, and a machine without bash-completion installed must still get the flags right when the file is sourced by hand
- **`compopt` is guarded**: `compopt -o dirnames 2>/dev/null || true`. It arrived in bash 4.0, so on the 3.2 macOS ships a bare call prints "command not found" into the middle of a completion and returns nonzero under the caller's `set -e`; guarded, the file quietly degrades to plain word completion
- **Candidates are collected with a `while IFS= read -r` loop, never `mapfile`.** Same floor one level up — `mapfile` is also 4.0, and this file is sourced by whatever bash the user has. `COMPREPLY=( $(compgen -W … ) )` is the other tempting spelling and is exactly what SC2207 exists to reject, since it word-splits and glob-expands the candidates it is supposed to pass through
- **`# shellcheck shell=bash` is the first line.** The file has no shebang to declare its dialect, and a shebang on a file that is only ever sourced would be a dead line. Without the directive shellcheck cannot infer the intended dialect, so `check-sh.sh -c` requires it

## The zsh file

- **`#compdef <cmd>` is the first line, and it plays the shebang's role.** The file is never executed, only autoloaded, so a shebang would be dead in it too; that line is the binding, and the `_<cmd>` filename is only convention
- **It defines its function and ends by calling it** — `_<cmd> "$@"` as the last line, the autoload convention. A pair sourced from a checkout rather than installed is not on `$fpath` and cannot be autoloaded, so it registers itself with `compdef _fn cmd`, which also makes `./cmd` complete, since zsh dispatches on the command's basename
- **`zsh -n` is the parse check.** shellcheck has no zsh dialect, and `bash -n` on a `#compdef` file reports syntax errors that are not errors, so the parse is zsh's to make; `shfmt` reads the dialect under `-ln zsh` and can format one ([lint.md](lint.md))

## Subcommands, and where the words come from

Both files take the same shape once a tool has subcommands: word 1 offers the subcommand list, and each subcommand's own words live in its own branch — a `case` over `${COMP_WORDS[1]}` guarded by `$COMP_CWORD` in bash, a `case` over `$words[2]` guarded by `$CURRENT` in zsh. Each list is spelled once per file; a list spelled twice inside one file is the same drift the checker exists to catch, one file down

A value is static when it is known while the file is being written — subcommand names, flags, a fixed enumeration — and static values are spelled out and held to the dispatcher by machine. A value is dynamic when it is state the tool learns at runtime: profiles, installed effects, saved names. Dynamic values are produced by calling the tool at the moment TAB is pressed, which puts two requirements back on the tool. The listing command must work without root, because `_sudo` restarts completion for the ordinary user before the privileged command ever runs, and it must print bare names on stdout with its noise on stderr, because the output goes straight into `compgen -W` or `_describe`

Generating both files from an argparse-style declaration removes the hand-written list altogether, at the price of dragging the tool into whatever framework the generator can read. For a CLI of this size the hand-written list plus a drift check is shorter, and it is the only one of the two that covers the zsh file as well

## Hand-written on purpose, drift-checked by machine

`check-sh.sh -c completions/<cmd>.bash completions/_<cmd> <cmd>` holds both files to the script's own dispatcher and flag parsers, in both directions:

- forward, every subcommand the dispatcher has and every flag some parser accepts must appear in **both** files as a whole token — `SUB is dispatched but absent from FILE`
- backward, every `--flag` either file offers must be parsed by some branch of the script — `FLAG is offered by FILE but not parsed`
- a run that extracts zero flags is a refusal rather than a pass, because a broken extractor must never read as "no drift"

Only what a file offers is searched, not the prose around it. Comments are dropped from both files, and so is a case pattern that opens a line — `-l)`, `--prefix | --destdir)` — since that arm handles a flag's value and offers nothing; from the zsh file, the text in `[...]` after an option, the description after the colon of a `'sub:description'` entry and the message between the first colons of an `'N:message:action'` spec are also dropped, while the action itself, `(run stop help)`, stays. Otherwise a subcommand removed from the offered list can pass because another entry's description still says its name. The quotes are walked a line at a time, so a quoted string spanning lines is read as written

"Whole token" requires more than a substring match: `-f` must not pass on a file offering only `--force`, and `-h` must not pass on one offering only `--help`. `grep -w` is wrong in the other direction, treating the hyphen as a word separator and so accepting `--help` inside `--help-all`. The matcher is `(^|[^[:alnum:]_-])FLAG([^[:alnum:]_-]|$)`, with the hyphen inside the token class on purpose

Falsify it once, when wiring it into a repository: plant a fake flag in a copy of the script, watch the check go red, delete the copy. The check's job is proven by that red run and by no green one. Skeletons for both files are in [`templates/completions/`](../templates/completions/), and they are the text the checker plants its own defects into on every run

## Next

The help is the truth these two files mirror, and what it must list is [help.md](help.md); the manual pages behind the two dialects are in [sources.md](sources.md#completions)
