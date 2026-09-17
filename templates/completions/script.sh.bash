# shellcheck shell=bash
# Tab completion for script.sh in bash. Hand-written on purpose and drift-checked by
# machine: check-sh.sh -c holds every word here to the script's dispatcher and parsers.
# Builtins only, so it works without the bash-completion package and under the bash 3.2
# a stock macOS sources it with
_script_sh() {
  local cur prev words
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  if ((COMP_CWORD == 1)); then
    words="run stop help"
  else
    case "${COMP_WORDS[1]}" in
      run)
        case "$prev" in
          -l)
            compopt -o dirnames 2>/dev/null || true
            return
            ;;
        esac
        words="-n --dry-run -l"
        ;;
      *) words="" ;;
    esac
  fi
  COMPREPLY=()
  while IFS= read -r word; do
    [[ -n "$word" ]] && COMPREPLY+=("$word")
  done < <(compgen -W "$words" -- "$cur")
}
complete -F _script_sh script.sh
