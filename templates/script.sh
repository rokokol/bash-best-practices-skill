#!/usr/bin/env bash
# script.sh — one line saying what it is, in the shape every script of the family has.
#
#   script.sh run [-n|--dry-run] [-l DIR]    do the thing, in DIR
#   script.sh stop                           stop doing it
#
#   -n, --dry-run   say what would be done and do nothing
#   -l DIR          the log directory (default: $SCRIPT_LOGDIR, else the current one)
#
# Environment: SCRIPT_LOGDIR is the log directory when -l is not given.
# Exit 0 done, 1 when the thing asked about is wrong, 2 on a usage error.
# Nothing here reaches the network. Needs bash 3.2 and POSIX tools only.
set -euo pipefail

# The whole header, however long it grows: up to the first line that is not a comment
usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

fail() { # the thing asked about is wrong
  printf 'script.sh: %s\n' "$1" >&2
  exit 1
}

die() { # the request itself is wrong
  printf 'script.sh: %s\n' "$1" >&2
  exit 2
}

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# >>> EXAMPLE: the subcommands, one cmd_<name>() each, with their parser inside
cmd_run() {
  local dry=0 logdir="${SCRIPT_LOGDIR:-.}"
  while (($#)); do
    case "$1" in
      -n | --dry-run)
        dry=1
        shift
        ;;
      -l)
        # Not ${2:?}: that exits 1 with bash's own message, and a usage error is 2
        (($# >= 2)) || die "-l needs a directory"
        logdir="$2"
        shift 2
        ;;
      -*) die "no such flag: $1" ;;
      *) break ;;
    esac
  done
  [[ -d "$logdir" ]] || fail "$logdir is not a directory"
  if ((dry)); then
    printf 'would run in %s\n' "$logdir"
  else
    printf 'ran in %s from %s\n' "$logdir" "$HERE"
  fi
}

cmd_stop() {
  printf 'stopped\n'
}
# <<< EXAMPLE

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
    printf 'script.sh: no such subcommand: %s\n\n' "$cmd" >&2
    usage >&2
    exit 2
    ;;
esac
