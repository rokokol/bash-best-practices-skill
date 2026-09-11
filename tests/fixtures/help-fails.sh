#!/usr/bin/env bash
# A script whose --help exits nonzero: check-sh.sh must refuse it, since there is no
# help to hold the code to.
set -euo pipefail
cmd="${1:-}"
(($# == 0)) || shift
case "$cmd" in
  run) : ;;
  -h | --help | help) exit 1 ;;
  *) exit 2 ;;
esac
