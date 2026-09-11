#!/usr/bin/env bash
# One construct per line that the bash 3.2 macOS ships, or its BSD userland, does not
# have. check-sh.sh's proxy grep must catch every one of them in a script that claims
# 3.2, and must let every one of them pass in a script that does not. This file is a
# fixture and is never linted or sourced, which is why it may hold them at all.
[[ -v SOMEVAR ]]
mapfile -t lines <f
readarray -t lines <f
declare -A map
local -A map
declare -n ref=name
local -n ref=name
echo "${name,,}"
echo "${name^^}"
echo "${name@Q}"
case x in a) ;;& b) ;; esac
cmd |& tee log
wait -n
sort -rV
grep -P '\d'
readlink -f "$0"
date -d yesterday
mktemp -p /tmp
mktemp -t prefix
mktemp --tmpdir
mktemp --suffix=.log
