#!/usr/bin/env bash
# One construct per line that a bash older than the floor in the first column does not
# have, or that a BSD userland reads another way. The columns are separated by a tab:
# a floor as bash's NEWS gives it (400 is 4.0, 502 is 5.2), or `bsd` for a userland flag
# that is GNU-only or spelled differently there. check-sh.sh's proxy must catch every row
# in a script whose claim is below that floor, and must stay quiet in one that declares it.
# This file is a fixture and is never linted or sourced, which is why it may hold them.
400	mapfile -t lines <f
400	readarray -t lines <f
400	declare -A map
400	local -A map
400	echo "${name,,}"
400	echo "${name^^}"
400	case x in a) ;;& b) ;; esac
400	cmd |& tee log
400	read -r -t 0.5 line
400	shopt -s globstar
401	exec {fd}<f
402	[[ -v SOMEVAR ]]
402	echo "${name:0:-1}"
403	declare -n ref=name
403	local -n ref=name
403	wait -n
404	echo "${name@Q}"
502	echo "${name//"$a"/"$b"}"
502	echo "${name//</&lt;}"
bsd	sort -rV
bsd	grep -P '\d'
bsd	readlink -f "$0"
bsd	date -d yesterday
bsd	mktemp -p /tmp
bsd	mktemp -t prefix
bsd	mktemp --tmpdir
bsd	mktemp --suffix=.log
bsd	sed -i 's/a/b/' f
bsd	sed --in-place 's/a/b/' f
bsd	grep -r --exclude-dir=.git x .
bsd	timeout 5 cmd
bsd	tar -x --wildcards -f a.tar '*.sh'
bsd	tar -c --null -T - -f a.tar
