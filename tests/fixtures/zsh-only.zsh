#compdef probe
# Not a completion anyone loads: a zsh file that bash cannot parse, kept so the claim in
# completions.md and harness.md — that `bash -n` on a `#compdef` file reports syntax errors
# that are not errors — is proved by a run rather than restated in prose. Every real zsh
# file in this family happens to sit in the subset bash also parses, so without this one
# nothing here would notice if the claim stopped being true
_probe() {
  # A glob qualifier: (.om[1]) is "plain files, newest first, take the first". bash has no
  # such syntax and never has, which is what makes it the durable half of this fixture
  local -a newest
  newest=(*(.om[1]))
  compadd -- "${newest[@]}"
}
_probe "$@"
