#compdef script.sh
# Tab completion for script.sh in zsh. Hand-written on purpose and drift-checked by
# machine: check-sh.sh -c holds every word here to the script's dispatcher and parsers.
# The #compdef line binds it when the file sits on $fpath as _script.sh, and the last
# line calls the function, which is the autoload convention.
_script_sh() {
  local -a subcommands
  subcommands=(
    'run:do the thing'
    'stop:stop doing it'
    'help:show the help'
  )
  _arguments -C \
    '1:subcommand:->subcommand' \
    '*::arguments:->arguments'
  case "$state" in
    subcommand) _describe 'subcommand' subcommands ;;
    arguments)
      case "${words[1]}" in
        run)
          _arguments \
            '(-n --dry-run)'{-n,--dry-run}'[say what would be done]' \
            '-l[the log directory]:directory:_directories'
          ;;
      esac
      ;;
  esac
}
_script_sh "$@"
