#!/bin/sh
# tests/leftovers.sh — tests for skills/verify/scripts/leftovers, with real child processes.
#
# Plain POSIX sh, no network. Starts sleepers with and without this test's own MARCSH_SESSION
# marker (a marked grandchild left behind by `sh -c 'sleep … &'`, a MARCSH_INFRA=1 one, a daemon
# leading its own session with a child, one whose command line holds secret-looking values, one
# that turns into an unmarked process on TERM, and a marked "root" running the script with a
# sleeper of its own), checks the listing, --count and --stop, and kills every child it started
# before it exits.
#
# Usage:
#   sh tests/leftovers.sh                     script run with sh
#   TEST_SH=dash dash tests/leftovers.sh      ... with dash
#   TEST_SH=bash bash tests/leftovers.sh      ... with bash

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
TSH=${TEST_SH:-sh}
LO=$ROOT/skills/verify/scripts/leftovers

# has_tty PID: PID has a controlling terminal.
has_tty() {
  if [ -r "/proc/$1/stat" ]; then
    [ "$(sed 's/.*) //' "/proc/$1/stat" | awk '{ print $5 }')" != 0 ]
  else
    case $(ps -o tt= -p "$1" 2>/dev/null | tr -d ' ') in '' | '??' | -) return 1 ;; esac
  fi
}

# Run from a terminal, every child would have it too and be listed as possibly yours: the test
# runs again in a session of its own, without a terminal (perl forks, the child calls setsid).
if [ -z "${LEFTOVERS_TEST_DETACHED-}" ] && has_tty $$; then
  if command -v perl >/dev/null 2>&1; then
    LEFTOVERS_TEST_DETACHED=1 exec perl -MPOSIX -e '
      my $p = fork; die "fork: $!" unless defined $p;
      if (!$p) { POSIX::setsid(); exec @ARGV or exit 127 }
      waitpid($p, 0); exit($? >> 8)' "$TSH" "$0" "$@"
  fi
  printf 'SKIP this test needs perl to run without a controlling terminal\n'
  exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rsc-leftovers.XXXXXX") || exit 1
PIDS=""
TSH_ABS=$(command -v "$TSH") || exit 1

# Kill every child this test started (and any marked process the script listed), then the temp dir.
cleanup() {
  for p in $PIDS; do kill -KILL "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# This test must not inherit a real session's marker: its children are marked only on purpose.
unset MARCSH_SESSION MARCSH_CALL MARCSH_INFRA || :
S="leftovers-test-$$-$(date +%s)"

PASSES=0
FAILS=0
ok() { PASSES=$((PASSES + 1)); printf 'ok   %s\n' "$1"; }
no() { FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '     %s\n' "$2"; return 0; }
check() { if eval "$2"; then ok "$1"; else no "$1" "${3-}"; fi; }

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

# child_of PID: the first child of PID.
child_of() { ps -A -o pid=,ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1; exit }'; }

# lo ARGS...: run the script as a process of session $S.
lo() { MARCSH_SESSION=$S "$TSH" "$LO" "$@"; }

# line_for PID TEXT: the listing line of PID, empty if absent.
line_for() { printf '%s\n' "$2" | awk -v p="$1" 'index($1, p ":") == 1'; }
# target_for PID TEXT: its PID:STARTKEY.
target_for() { line_for "$1" "$2" | awk '{ print $1 }'; }

# --- the sleeper ---------------------------------------------------------------------------
# macOS hides the environment of Apple's own binaries (/bin/sleep, /bin/sh) from `ps -E`, so the
# script cannot see their marker there. The children are therefore `sleep` on Linux and, on macOS,
# the first of sleep, node, python3 whose marker `ps -E` can read. `sleeper N [ARG...]` sleeps N
# seconds (N may be written 3607.000…; the ARGs only show in its command line); `stubborn N` does
# the same and ignores TERM; `chameleon N` becomes an unmarked sleeper (same pid) on TERM;
# spawner.sh sleeps N and starts a child sleeping M.
NODE_SLEEP='setTimeout(function(){},+process.argv[1]*1000)'
PY_SLEEP='import sys,time; time.sleep(float(sys.argv[1]))'
sleeper() {
  case $KIND in
    sleep) [ $# -gt 1 ] && exec sh -c 'sleep "$0"; :' "$@"; exec sleep "$1" ;;
    node) exec node -e "$NODE_SLEEP" "$@" ;;
    python3) exec python3 -c "$PY_SLEEP" "$@" ;;
  esac
}
stubborn() {
  trap '' TERM
  case $KIND in
    node) exec node -e "process.on('SIGTERM',function(){});$NODE_SLEEP" "$1" ;;
    *) sleeper "$1" ;;
  esac
}
# (a file, so that it can run as the leader of a new session: daemon below)
cat > "$TMP/spawner.sh" << 'EOF'
KIND=$1 NODE_SLEEP=$2 PY_SLEEP=$3
case $KIND in
  sleep) exec sh -c 'sleep "$1" & exec sleep "$0"' "$4" "$5" ;;
  node) exec node -e "require('child_process').spawn(process.execPath,['-e','$NODE_SLEEP',process.argv[2]],{stdio:'ignore'});$NODE_SLEEP" "$4" "$5" ;;
  python3) exec python3 -c "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c','$PY_SLEEP',sys.argv[2]]); time.sleep(float(sys.argv[1]))" "$4" "$5" ;;
esac
EOF
chameleon() {
  case $KIND in
    sleep) exec sh -c 'trap "exec env -u MARCSH_SESSION sleep $0" TERM; sleep "$0" & wait' "$1" ;;
    node) exec node -e "process.on('SIGTERM',function(){process.execve(process.execPath,[process.execPath,'-e','$NODE_SLEEP','$1'],{})});$NODE_SLEEP" "$1" ;;
    python3) exec python3 -c "import os,signal,sys,time; signal.signal(signal.SIGTERM, lambda *a: os.execve(sys.executable, [sys.executable, '-c', '$PY_SLEEP', sys.argv[1]], {})); time.sleep(float(sys.argv[1]))" "$1" ;;
  esac
}
# daemon CMD...: exec CMD as the leader of a new session.
daemon() {
  if command -v perl >/dev/null 2>&1; then
    exec perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' "$@"
  fi
  exec setsid "$@"
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
CHAMELEON=1
[ "$KIND" != node ] || node -e 'process.exit(typeof process.execve === "function" ? 0 : 1)' || CHAMELEON=0
DAEMON=1
command -v perl >/dev/null 2>&1 || command -v setsid >/dev/null 2>&1 || DAEMON=0

# --- children ------------------------------------------------------------------------------
mark() { MARCSH_SESSION=$S; export MARCSH_SESSION; }
(mark; sleeper 3601) >/dev/null 2>&1 &
M1=$!
(mark; MARCSH_CALL=call-1; export MARCSH_CALL; sleeper 3602) >/dev/null 2>&1 &
M2=$!
(sleeper 3603) >/dev/null 2>&1 &
U1=$!
(MARCSH_SESSION=${S}x; export MARCSH_SESSION; sleeper 3604) >/dev/null 2>&1 &
O1=$!
(MARCSH_SESSION=x$S; export MARCSH_SESSION; sleeper 3605) >/dev/null 2>&1 &
O2=$!
(mark; stubborn 3608) >/dev/null 2>&1 &
T1=$!
ZEROS=$(printf '0%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)
ZEROS=$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS$ZEROS
(mark; sleeper "3607.$ZEROS") >/dev/null 2>&1 &
L1=$!
# A marked grandchild: the subshell exits at once and leaves its sleeper behind, reparented.
(mark; (sleeper 3606) >/dev/null 2>&1 & echo $! > "$TMP/gc.pid")
GC=$(cat "$TMP/gc.pid")
# marcsh's own machinery (MARCSH_INFRA=1): never listed, never stopped.
(mark; MARCSH_INFRA=1; export MARCSH_INFRA; sleeper 3609) >/dev/null 2>&1 &
I1=$!
# Secret-looking values in the command line: listed redacted.
(mark; sleeper 3610 --api-token=SEKRET1 --password SEKRET2 Bearer SEKRET3) >/dev/null 2>&1 &
R1=$!
(mark; sleeper 3614 https://b:SEKRET4@h mysql -pSEKRET5 API_TOKEN=SEKRET6) >/dev/null 2>&1 &
R2=$!
PIDS="$M1 $M2 $U1 $O1 $O2 $T1 $L1 $GC $I1 $R1 $R2"
EXPECT=7
# With plain sleep, R1, R2 and the chameleon are shells with a sleep child, listed too.
[ "$KIND" != sleep ] || EXPECT=$((EXPECT + 2))
D1='' DC=''
if [ "$DAEMON" = 1 ]; then
  # A daemon: leads its own session, with a child (like tmux and a pane).
  (mark; daemon "$TSH_ABS" "$TMP/spawner.sh" "$KIND" "$NODE_SLEEP" "$PY_SLEEP" 3611 3612) >/dev/null 2>&1 &
  D1=$!
  PIDS="$PIDS $D1"
  EXPECT=$((EXPECT + 2))
fi
CH=''
if [ "$CHAMELEON" = 1 ]; then
  (mark; chameleon 3613) >/dev/null 2>&1 &
  CH=$!
  PIDS="$PIDS $CH"
  EXPECT=$((EXPECT + 1))
  [ "$KIND" != sleep ] || EXPECT=$((EXPECT + 1))
fi
sleep 1
if [ -n "$D1" ]; then
  DC=$(child_of "$D1")
  PIDS="$PIDS $DC"
fi

# --- no marker -----------------------------------------------------------------------------
out=$("$TSH" "$LO" 2>"$TMP/err"); rc=$?
check 'no MARCSH_SESSION: note on stderr, exit 1' '[ "$rc" = 1 ] && [ -z "$out" ] && grep -q MARCSH_SESSION "$TMP/err"' "rc=$rc out=$out err=$(cat "$TMP/err")"
out=$(MARCSH_SESSION= "$TSH" "$LO" --count 2>/dev/null); rc=$?
check 'empty MARCSH_SESSION: exit 1' '[ "$rc" = 1 ] && [ -z "$out" ]' "rc=$rc out=$out"

# --- listing -------------------------------------------------------------------------------
list=$(lo); rc=$?
check 'listing exits 0' '[ "$rc" = 0 ]' "rc=$rc"
printf '%s\n' "$list" > "$TMP/list"
for p in $(awk '{ sub(/:.*/, "", $1); print $1 }' "$TMP/list"); do PIDS="$PIDS $p"; done

l=$(line_for "$M1" "$list")
check 'marked child listed as: pid:startkey  age  rssMB  command' \
  'printf "%s\n" "$l" | grep -Eq "^$M1:[0-9]+  [0-9:-]+  [0-9]+\.[0-9]MB  [^ ].* 3601\$"' "line=[$l]"
check 'marked child with MARCSH_CALL listed' '[ -n "$(line_for "$M2" "$list")" ]'
check 'marked grandchild (left by a shell that exited) listed' '[ -n "$(line_for "$GC" "$list")" ]' "$list"
check 'marked TERM-ignoring child listed' '[ -n "$(line_for "$T1" "$list")" ]'
for p in "$U1:unmarked" "$O1:other session (value + suffix)" "$O2:other session (prefix + value)" "$I1:MARCSH_INFRA=1" "$$:the test shell"; do
  check "not listed: ${p#*:}" '[ -z "$(line_for "${p%%:*}" "$list")" ]' "$list"
done
check 'the environment is not printed' '! grep -q "MARCSH_SESSION=" "$TMP/list"' "$list"
check 'no ordinary leftover is flagged possibly yours' \
  '! printf "%s\n" "$(line_for "$M1" "$list")$(line_for "$GC" "$list")$(line_for "$R1" "$list")" | grep -q "possibly yours"' "$list"

l=$(line_for "$L1" "$list")
cmd=$(printf '%s\n' "$l" | awk '{ sub(/^[^ ]+  [^ ]+  [^ ]+  /, ""); print }')
check 'long command cut to 120 characters' '[ -n "$l" ] && [ "${#cmd}" -eq 120 ]' "len=${#cmd} line=[$l]"

l=$(line_for "$R1" "$list")
l2=$(line_for "$R2" "$list")
check 'secret-looking values are redacted' \
  'case $l$l2 in *SEKRET*) false ;; *" 3610 --api-token=*** --password *** Bearer ***"*" 3614 https://b:***@h mysql -p*** API_TOKEN=***") true ;; *) false ;; esac' "line=[$l] [$l2]"

if [ -n "$D1" ]; then
  l=$(line_for "$D1" "$list")
  check 'a daemon leading its own session is flagged possibly yours' \
    'case $l in *" [possibly yours: it leads its own session"*) true ;; *) false ;; esac' "line=[$l] $list"
  l=$(line_for "$DC" "$list")
  check 'the daemon'"'"'s child is flagged possibly yours' \
    'case $l in *" [possibly yours: it runs under pid $D1,"*) true ;; *) false ;; esac' "child=$DC line=[$l]"
else
  printf 'skip daemon tests (neither perl nor setsid)\n'
fi

# Expected: M1, M2, GC, T1, L1, R1, R2 (+ D1, DC, CH). Nothing of the script itself may show.
self=$(grep 'leftovers' "$TMP/list")
check 'the script and its own processes are not listed' '[ -z "$self" ]' "$self"
n=$(grep -c . "$TMP/list")
check "exactly the marked leftovers are listed ($EXPECT)" '[ "$n" = "$EXPECT" ]' "n=$n: $list"

# --- --count -------------------------------------------------------------------------------
c=$(lo --count); rc=$?
check "--count prints the number ($c)" '[ "$rc" = 0 ] && [ "$c" = "$EXPECT" ]' "rc=$rc count=[$c]"
c2=$(MARCSH_SESSION=$S sh -c '"$0" "$1" --count; :' "$TSH" "$LO")
check 'a marked parent shell is not counted' '[ "$c2" = "$EXPECT" ]' "via parent=$c2 direct=$c"

# --- PATH is not trusted ---------------------------------------------------------------------
FAKE=$TMP/fakebin
mkdir -p "$FAKE"
for t in ps awk tr grep sed; do
  printf '#!/bin/sh\necho "%s" >> "%s"\necho "%s 1 %s S ?? Mon Jan  1 00:00:00 2024 100 sleep MARCSH_SESSION=%s"\n' "$t" "$TMP/fake.log" "$U1" "$U1" "$S" > "$FAKE/$t"
  chmod +x "$FAKE/$t"
done
: > "$TMP/fake.log"
fl=$(PATH=$FAKE:$PATH MARCSH_SESSION=$S "$TSH_ABS" "$LO" 2>&1)
check 'a ps (or awk, tr, grep, sed) earlier in PATH is never run' '[ ! -s "$TMP/fake.log" ] && [ -z "$(line_for "$U1" "$fl")" ]' "log=$(cat "$TMP/fake.log") out=$fl"
u1=$(MARCSH_SESSION=$S PATH=$FAKE:$PATH "$TSH_ABS" "$LO" --stop "$U1:$(target_for "$M1" "$list" | cut -d: -f2)" --confirmed 2>&1); rc=$?
check '--stop with a fake ps in PATH still refuses an unmarked pid' '[ "$rc" = 1 ] && running "$U1" && [ ! -s "$TMP/fake.log" ]' "rc=$rc out=$u1"

# --- a process under the script's marcsh-like root -----------------------------------------
# A marked root (its parent, this test, is not marked) that runs the script and has a sleeper of
# its own: the sleeper is still under the root (like a running call or an MCP server under the
# Claude CLI), so the script run from inside the root neither lists nor stops it.
case $KIND in
  node) SLEEPCMD="node -e '$NODE_SLEEP' 3620" ;;
  python3) SLEEPCMD="python3 -c '$PY_SLEEP' 3620" ;;
  sleep) SLEEPCMD="sleep 3620" ;;
esac
RS_SCRIPT='T=$1; '"$SLEEPCMD"' & echo $! > "$T/rs.pid"
  while [ ! -f "$T/rs.go" ]; do sleep 0.2; done
  "$2" "$3" > "$T/rs.list" 2>&1
  "$2" "$3" --stop "$(cat "$T/rs.target")" --confirmed > "$T/rs.stop" 2>&1; echo $? > "$T/rs.rc"
  kill $!'
(
  mark
  case $KIND in
    node) exec node -e 'process.exitCode = require("child_process").spawnSync("/bin/sh", ["-c", process.argv[1], "sh", process.argv[2], process.argv[3], process.argv[4]], { stdio: "inherit" }).status' "$RS_SCRIPT" "$TMP" "$TSH_ABS" "$LO" ;;
    python3) exec python3 -c 'import subprocess,sys; sys.exit(subprocess.call(["/bin/sh", "-c", sys.argv[1], "sh"] + sys.argv[2:]))' "$RS_SCRIPT" "$TMP" "$TSH_ABS" "$LO" ;;
    sleep) exec sh -c "$RS_SCRIPT" sh "$TMP" "$TSH_ABS" "$LO" ;;
  esac
) >/dev/null 2>&1 &
RT=$!
PIDS="$PIDS $RT"
_i=0
while [ ! -s "$TMP/rs.pid" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
sleep 1
RS=$(cat "$TMP/rs.pid" 2>/dev/null)
PIDS="$PIDS $RS"
outside=$(lo)
target_for "$RS" "$outside" > "$TMP/rs.target"
: > "$TMP/rs.go"
wait "$RT" 2>/dev/null
rsl=$(cat "$TMP/rs.list" 2>/dev/null)
check 'seen from outside the root, its sleeper is a leftover' '[ -n "$(line_for "$RS" "$outside")" ]' "rs=$RS outside=$outside"
check 'from inside the root: its own sleeper is not listed' '[ -n "$RS" ] && [ -z "$(line_for "$RS" "$rsl")" ]' "rs=$RS list=$rsl"
check 'from inside the root: the leftovers outside it still are' '[ -n "$(line_for "$M1" "$rsl")" ]' "list=$rsl"
check 'from inside the root: --stop refuses its sleeper (still under marcsh)' \
  '[ "$(cat "$TMP/rs.rc" 2>/dev/null)" = 1 ] && grep -q "^refused .*under marcsh" "$TMP/rs.stop"' "rc=$(cat "$TMP/rs.rc" 2>/dev/null) out=$(cat "$TMP/rs.stop" 2>/dev/null)"
kill "$RS" 2>/dev/null

# --- --stop refuses ------------------------------------------------------------------------
list=$(lo)
key1=$(target_for "$M1" "$list" | cut -d: -f2)
for p in "$U1:unmarked" "$O1:other session" "$$:the test shell" "$I1:MARCSH_INFRA=1"; do
  pid=${p%%:*}
  out=$(lo --stop "$pid:$key1" --confirmed 2>&1); rc=$?
  check "--stop refuses ${p#*:} and leaves it running" '[ "$rc" = 1 ] && printf "%s" "$out" | grep -q "^refused" && running "$pid"' "rc=$rc out=$out"
done
out=$(lo --stop "$M1" 2>&1); rc=$?
check '--stop refuses a bare pid' '[ "$rc" = 1 ] && printf "%s" "$out" | grep -q "^refused $M1:" && running "$M1"' "rc=$rc out=$out"
out=$(lo --stop "$M1:$((key1 + 7))" 2>&1); rc=$?
check '--stop refuses a reused pid (another start key)' '[ "$rc" = 1 ] && printf "%s" "$out" | grep -q "^refused $M1:.*another process" && running "$M1"' "rc=$rc out=$out"
out=$(lo --stop abc 2>&1); rc=$?
check '--stop refuses a non-pid' '[ "$rc" = 1 ] && printf "%s" "$out" | grep -q "^refused abc"' "rc=$rc out=$out"
out=$(lo --stop 2>&1); rc=$?
check '--stop with no pid is a usage error' '[ "$rc" = 2 ]' "rc=$rc out=$out"
out=$(lo --stop --confirmed 2>&1); rc=$?
check '--stop --confirmed with no pid is a usage error' '[ "$rc" = 2 ]' "rc=$rc out=$out"
out=$(lo --confirmed 2>&1); rc=$?
check '--confirmed without --stop is a usage error' '[ "$rc" = 2 ]' "rc=$rc out=$out"

if [ -n "$D1" ]; then
  td=$(target_for "$D1" "$list")
  out=$(lo --stop "$td" 2>&1); rc=$?
  check '--stop refuses a possibly-yours process without --confirmed' \
    '[ "$rc" = 1 ] && printf "%s" "$out" | grep -q "^refused $td: possibly yours" && running "$D1"' "rc=$rc out=$out"
  out=$(lo --stop --confirmed "$td" "$(target_for "$DC" "$list")" 2>&1); rc=$?
  check '--stop --confirmed stops possibly-yours processes' '[ "$rc" = 0 ] && ! running "$D1" && ! running "$DC"' "rc=$rc out=$out"
fi

# A mixed call stops the marked pid, refuses the unmarked one and exits 1.
t1=$(target_for "$M1" "$list")
out=$(lo --stop "$U1:$key1" "$t1" 2>&1); rc=$?
check '--stop with a mixed list: stops the marked, refuses the unmarked, exits 1' \
  '[ "$rc" = 1 ] && ! running "$M1" && running "$U1" && printf "%s" "$out" | grep -q "^stopped $t1\$"' "rc=$rc out=$out"
out=$(lo --stop "$t1" 2>&1); rc=$?
check '--stop on a pid already gone: gone, exit 0' '[ "$rc" = 0 ] && printf "%s" "$out" | grep -q "^gone $t1"' "rc=$rc out=$out"

# --- --stop stops marked pids --------------------------------------------------------------
out=$(lo --stop "$(target_for "$GC" "$list")" 2>&1); rc=$?
check '--stop stops the marked grandchild' '[ "$rc" = 0 ] && ! running "$GC"' "rc=$rc out=$out"

tt=$(target_for "$T1" "$list")
out=$(lo --stop "$tt" 2>&1); rc=$?
running "$T1" || { wait "$T1"; } 2>/dev/null
check '--stop kills a process that ignores TERM after the grace' \
  '[ "$rc" = 0 ] && ! running "$T1" && printf "%s" "$out" | grep -q "^stopped $tt (KILL"' "rc=$rc out=$out"

if [ -n "$CH" ]; then
  tc=$(target_for "$CH" "$list")
  out=$(lo --stop "$tc" 2>&1); rc=$?
  check '--stop reports a process still running (unmarked after TERM) as not stopped, sends no KILL' \
    '[ "$rc" = 1 ] && running "$CH" && printf "%s" "$out" | grep -q "^not stopped $tc: "' "rc=$rc out=$out"
  kill -KILL "$CH" 2>/dev/null
else
  printf 'skip still-running test (node without process.execve)\n'
fi

rest=$(lo | awk '{ print $1 }')
for p in $rest; do PIDS="$PIDS ${p%%:*}"; done
# shellcheck disable=SC2086
out=$(lo --stop --confirmed $rest 2>&1); rc=$?
check '--stop stops every remaining marked process' '[ "$rc" = 0 ]' "rc=$rc out=$out"
sleep 1
c=$(lo --count)
check '--count is 0 afterwards' '[ "$c" = 0 ]' "count=$c: $(lo)"
out=$(lo 2>/dev/null)
check 'listing is empty afterwards' '[ -z "$out" ]' "$out"

for p in "$U1:unmarked" "$O1:other session" "$O2:other session" "$I1:MARCSH_INFRA=1"; do
  check "still running: ${p#*:}" 'running "${p%%:*}"'
done

# --- cleanup -------------------------------------------------------------------------------
{ for p in $PIDS; do kill -KILL "$p" 2>/dev/null; done; wait; } 2>/dev/null
sleep 1
left=""
for p in $PIDS; do running "$p" && left="$left $p"; done
check 'every child is gone after cleanup' '[ -z "$left" ]' "$left"

printf '\n%s passed, %s failed (%s)\n' "$PASSES" "$FAILS" "$TSH"
[ "$FAILS" = 0 ]
