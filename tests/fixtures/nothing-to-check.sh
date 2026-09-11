#!/usr/bin/env bash
# A script with no dispatcher and no flag arm: check-sh.sh must refuse it rather than
# pass it, because a check with nothing to hold to the help would pass anything.
echo hi
