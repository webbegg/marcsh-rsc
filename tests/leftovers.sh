#!/bin/sh
# tests/leftovers.sh — tests for skills/verify/scripts/leftovers, with real child processes.
#
# Plain POSIX sh, no network. Starts `sleep` children with and without this test's own
# MARCSH_SESSION marker (plus a marked grandchild left behind by `sh -c 'sleep … &'`), checks the
# listing, --count and --stop, and kills every child it started before it exits.
#
# Usage:
#   sh tests/leftovers.sh                     script run with sh
#   TEST_SH=dash dash tests/leftovers.sh      ... with dash
#   TEST_SH=bash bash tests/leftovers.sh      ... with bash

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
TSH=${TEST_SH:-sh}
LO=$ROOT/skills/verify/scripts/leftovers

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rsc-leftovers.XXXXXX") || exit 1
PIDS=""

# Kill every child this test started (and any marked process the script listed), then the temp dir.
cleanup() {
  for p in $PIDS; do kill -KILL "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# This test must not inherit a real session's marker: its children are marked only on purpose.
unset MARCSH_SESSION MARCSH_CALL || :
S="leftovers-test-$$-$(date +%s)"

PASSES=0
FAILS=0
ok() { PASSES=$((PASSES + 1)); printf 'ok   %s\n' "$1"; }
no() { FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '     %s\n' "$2"; return 0; }

# running PID: alive and not a zombie (a stopped child of this shell stays a zombie until reaped).
running() {
  kill -0 "$1" 2>/dev/null || return 1
  if [ -r "/proc/$1/stat" ]; then
    _s=$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -c1)
  else
    _s=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' | cut -c1)
  fi
  [ -n "$_s" ] && [ "$_s" != Z ]
}

# lo ARGS...: run the script as a process of session $S.
lo() { MARCSH_SESSION=$S "$TSH" "$LO" "$@"; }

# line_for PID TEXT: the listing line of PID, empty if absent.
line_for() { printf '%s\n' "$2" | awk -v p="$1" '$1 == p'; }

# --- the sleeper ---------------------------------------------------------------------------
# macOS hides the environment of Apple's own binaries (/bin/sleep, /bin/sh) from `ps -E`, so the
# script cannot see their marker there. The children are therefore `sleep` on Linux and, on macOS,
# the first of sleep, node, python3 whose marker `ps -E` can read. `sleeper N` sleeps N seconds
# (N may be written 3607.000…); `stubborn N` does the same and ignores TERM.
NODE_SLEEP='setTimeout(function(){},+process.argv[1]*1000)'
PY_SLEEP='import sys,time; time.sleep(float(sys.argv[1]))'
sleeper() {
  case $KIND in
    sleep) exec sleep "$1" ;;
    node) exec node -e "$NODE_SLEEP" "$1" ;;
    python3) exec python3 -c "$PY_SLEEP" "$1" ;;
  esac
}
stubborn() {
  trap '' TERM
  case $KIND in
    node) exec node -e "process.on('SIGTERM',function(){});$NODE_SLEEP" "$1" ;;
    *) sleeper "$1" ;;
  esac
}
visible() {
  [ "$(uname -s)" = Linux ] && return 0
  ps -E -ww -o command= -p "$1" 2>/dev/null | grep -q "MARCSH_SESSION=$S-probe"
}
KIND=""
for k in sleep node python3; do
  command -v "$k" >/dev/null 2>&1 || continue
  KIND=$k
  (MARCSH_SESSION=$S-probe; export MARCSH_SESSION; sleeper 30) >/dev/null 2>&1 &
  probe=$!
  sleep 1
  if visible "$probe"; then kill "$probe" 2>/dev/null; wait "$probe" 2>/dev/null; break; fi
  kill "$probe" 2>/dev/null; wait "$probe" 2>/dev/null
  KIND=""
done
if [ -z "$KIND" ]; then
  printf 'SKIP no sleeper whose environment ps -E can read (macOS hides it for Apple binaries;\n'
  printf '     install node or a non-Apple python3 to run these tests here)\n'
  exit 1
fi
printf 'sleeper: %s\n' "$KIND"

# --- children ------------------------------------------------------------------------------
(MARCSH_SESSION=$S; export MARCSH_SESSION; sleeper 3601) >/dev/null 2>&1 &
M1=$!
(MARCSH_SESSION=$S MARCSH_CALL=call-1; export MARCSH_SESSION MARCSH_CALL; sleeper 3602) >/dev/null 2>&1 &
M2=$!
(sleeper 3603) >/dev/null 2>&1 &
U1=$!
(MARCSH_SESSION=${S}x; export MARCSH_SESSION; sleeper 3604) >/dev/null 2>&1 &
O1=$!
(MARCSH_SESSION=x$S; export MARCSH_SESSION; sleeper 3605) >/dev/null 2>&1 &
O2=$!
(MARCSH_SESSION=$S; export MARCSH_SESSION; stubborn 3608) >/dev/null 2>&1 &
T1=$!
ZEROS=$(printf '0%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
ZEROS=$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS
(MARCSH_SESSION=$S; export MARCSH_SESSION; sleeper "3607.$ZEROS") >/dev/null 2>&1 &
L1=$!
# A marked grandchild: the subshell exits at once and leaves its sleeper behind, reparented.
(MARCSH_SESSION=$S; export MARCSH_SESSION; (sleeper 3606) >/dev/null 2>&1 & echo $! > "$TMP/gc.pid")
GC=$(cat "$TMP/gc.pid")
PIDS="$M1 $M2 $U1 $O1 $O2 $T1 $L1 $GC"
sleep 1

# --- no marker -----------------------------------------------------------------------------
out=$("$TSH" "$LO" 2>"$TMP/err"); rc=$?
if [ "$rc" = 1 ] && [ -z "$out" ] && grep -q 'MARCSH_SESSION' "$TMP/err"; then
  ok 'no MARCSH_SESSION: note on stderr, exit 1'
else
  no 'no MARCSH_SESSION: note on stderr, exit 1' "rc=$rc out=$out err=$(cat "$TMP/err")"
fi
out=$(MARCSH_SESSION= "$TSH" "$LO" --count 2>/dev/null); rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && ok 'empty MARCSH_SESSION: exit 1' || no 'empty MARCSH_SESSION: exit 1' "rc=$rc out=$out"

# --- listing -------------------------------------------------------------------------------
list=$(lo); rc=$?
[ "$rc" = 0 ] && ok 'listing exits 0' || no 'listing exits 0' "rc=$rc"
printf '%s\n' "$list" > "$TMP/list"
for p in $(awk '{ print $1 }' "$TMP/list"); do PIDS="$PIDS $p"; done

l=$(line_for "$M1" "$list")
if printf '%s\n' "$l" | grep -Eq "^$M1  [0-9:-]+  [0-9]+\.[0-9]MB  [^ ].* 3601\$"; then
  ok 'marked child listed as: pid  age  rssMB  command'
else
  no 'marked child listed as: pid  age  rssMB  command' "line=[$l]"
fi
[ -n "$(line_for "$M2" "$list")" ] && ok 'marked child with MARCSH_CALL listed' || no 'marked child with MARCSH_CALL listed'
[ -n "$(line_for "$GC" "$list")" ] && ok 'marked grandchild (left by a shell that exited) listed' || no 'marked grandchild (left by a shell that exited) listed' "$list"
[ -n "$(line_for "$T1" "$list")" ] && ok 'marked TERM-ignoring child listed' || no 'marked TERM-ignoring child listed'
for p in "$U1:unmarked" "$O1:other session (value + suffix)" "$O2:other session (prefix + value)" "$$:the test shell"; do
  [ -z "$(line_for "${p%%:*}" "$list")" ] && ok "not listed: ${p#*:}" || no "not listed: ${p#*:}" "$list"
done
if grep -q 'MARCSH_SESSION=' "$TMP/list"; then no 'the environment is not printed' "$list"; else ok 'the environment is not printed'; fi

l=$(line_for "$L1" "$list")
cmd=$(printf '%s\n' "$l" | awk '{ sub(/^[^ ]+  [^ ]+  [^ ]+  /, ""); print }')
if [ -n "$l" ] && [ "${#cmd}" -eq 120 ]; then
  ok 'long command cut to 120 characters'
else
  no 'long command cut to 120 characters' "len=${#cmd} line=[$l]"
fi

# Expected: M1, M2, GC, T1, L1. Nothing of the script itself (its subshells, ps, awk) may show.
self=$(grep 'leftovers' "$TMP/list")
[ -z "$self" ] && ok 'the script and its own processes are not listed' || no 'the script and its own processes are not listed' "$self"
n=$(grep -c . "$TMP/list")
[ "$n" = 5 ] && ok 'exactly the marked processes are listed' || no 'exactly the marked processes are listed' "n=$n: $list"

# --- --count -------------------------------------------------------------------------------
c=$(lo --count); rc=$?
if [ "$rc" = 0 ] && [ "$c" = 5 ]; then
  ok "--count prints the number ($c)"
else
  no '--count prints the number' "rc=$rc count=[$c]"
fi

# A marked parent shell running the script: the caller's own chain is left out.
c2=$(MARCSH_SESSION=$S sh -c '"$0" "$1" --count; :' "$TSH" "$LO")
if [ "$c2" = 5 ]; then
  ok 'a marked parent shell is not counted'
else
  no 'a marked parent shell is not counted' "via parent=$c2 direct=$c"
fi

# --- --stop refuses unmarked pids ---------------------------------------------------------
for p in "$U1:unmarked" "$O1:other session" "$$:the test shell"; do
  pid=${p%%:*}
  out=$(lo --stop "$pid" 2>&1); rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q refused && running "$pid"; then
    ok "--stop refuses ${p#*:} and leaves it running"
  else
    no "--stop refuses ${p#*:} and leaves it running" "rc=$rc out=$out"
  fi
done
out=$(lo --stop abc 2>&1); rc=$?
[ "$rc" != 0 ] && ok '--stop refuses a non-pid' || no '--stop refuses a non-pid' "rc=$rc out=$out"
out=$(lo --stop 2>&1); rc=$?
[ "$rc" = 2 ] && ok '--stop with no pid is a usage error' || no '--stop with no pid is a usage error' "rc=$rc out=$out"

# A mixed call stops the marked pid, refuses the unmarked one and exits nonzero.
out=$(lo --stop "$U1" "$M1" 2>&1); rc=$?
if [ "$rc" != 0 ] && ! running "$M1" && running "$U1" && printf '%s' "$out" | grep -q "stopped $M1"; then
  ok '--stop with a mixed list: stops the marked, refuses the unmarked, exits nonzero'
else
  no '--stop with a mixed list: stops the marked, refuses the unmarked, exits nonzero' "rc=$rc out=$out"
fi

# --- --stop stops marked pids --------------------------------------------------------------
out=$(lo --stop "$GC" 2>&1); rc=$?
[ "$rc" = 0 ] && ! running "$GC" && ok '--stop stops the marked grandchild' || no '--stop stops the marked grandchild' "rc=$rc out=$out"

out=$(lo --stop "$T1" 2>&1); rc=$?
{ wait "$T1"; } 2>/dev/null
if [ "$rc" = 0 ] && ! running "$T1" && printf '%s' "$out" | grep -q "killed $T1"; then
  ok '--stop kills a process that ignores TERM after the grace'
else
  no '--stop kills a process that ignores TERM after the grace' "rc=$rc out=$out"
fi

rest=$(lo | awk '{ print $1 }')
for p in $rest; do PIDS="$PIDS $p"; done
# shellcheck disable=SC2086
out=$(lo --stop $rest 2>&1); rc=$?
[ "$rc" = 0 ] && ok '--stop stops every remaining marked process' || no '--stop stops every remaining marked process' "rc=$rc out=$out"
sleep 1
c=$(lo --count)
[ "$c" = 0 ] && ok '--count is 0 afterwards' || no '--count is 0 afterwards' "count=$c: $(lo)"
out=$(lo 2>/dev/null)
[ -z "$out" ] && ok 'listing is empty afterwards' || no 'listing is empty afterwards' "$out"

for p in "$U1:unmarked" "$O1:other session" "$O2:other session"; do
  running "${p%%:*}" && ok "still running: ${p#*:}" || no "still running: ${p#*:}"
done

# --- cleanup -------------------------------------------------------------------------------
{ for p in $PIDS; do kill -KILL "$p" 2>/dev/null; done; wait; } 2>/dev/null
sleep 1
left=""
for p in $PIDS; do running "$p" && left="$left $p"; done
[ -z "$left" ] && ok 'every child is gone after cleanup' || no 'every child is gone after cleanup' "$left"

printf '\n%s passed, %s failed (%s)\n' "$PASSES" "$FAILS" "$TSH"
[ "$FAILS" = 0 ]
