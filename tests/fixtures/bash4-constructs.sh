#!/usr/bin/env bash
# One construct per line that the bash 3.2 macOS ships, or its BSD userland, does not
# have or reads another way. check-sh.sh's proxy grep must catch every one of them in a
# script that claims 3.2, and must let every one of them pass in a script that does not.
# This file is a fixture and is never linted or sourced, which is why it may hold them.
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
echo "${name:0:-1}"
exec {fd}<f
read -r -t 0.5 line
shopt -s globstar
echo "${name//"$a"/"$b"}"
echo "${name//</&lt;}"
sed -i 's/a/b/' f
sed --in-place 's/a/b/' f
grep -r --exclude-dir=.git x .
timeout 5 cmd
tar -x --wildcards -f a.tar '*.sh'
tar -c --null -T - -f a.tar
