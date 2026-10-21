#!/bin/bash
# gate.sh -- the Win32 gate: every recording in ref/ replayed by W3DREP.EXE,
# its sums compared with DOS 1.11's: ref/*.ALL, every sum to the end (the
# SUMDUMP test build's), else ref/*.SUM, the first 64 (MAXCHECKS: what a
# release reports).  Needs the game's *.WL6 in run/.  StevenC & Claude (Anthropic), 2026-10-21.
cd "$(dirname "$0")/run" || exit 1
pass=0; fail=0
for m in ../ref/*.MPR; do
	n=$(basename "$m" .MPR)
	cp "$m" .
	W3DSUMS=1 timeout 900 ../W3DREP.EXE REPLAY $n.MPR FAST NOAL > $n.out 2>&1
	grep "^w32 step" $n.out | sed 's/^w32 step \([0-9]*\): /\1 /' > $n.w32
	if [ -f ../ref/$n.ALL ]; then cp ../ref/$n.ALL $n.dos; else tr -d '\r' < ../ref/$n.SUM > $n.dos; fi
	k=$(wc -l < $n.dos)
	head -n $k $n.w32 > $n.cmp
	if diff -q $n.dos $n.cmp > /dev/null; then
		echo "$n: all $k sums the same as DOS (to step $((k*50))); $(wc -l < $n.w32) made"
		pass=$((pass+1))
	else
		first=$(diff $n.dos $n.cmp | grep -m1 '^[<>]')
		echo "$n: DIFFERS -- first difference: $first"
		fail=$((fail+1))
	fi
done
echo "gate: $pass passed, $fail failed"
[ $fail = 0 ]
