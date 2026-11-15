#!/bin/sh
# tests/run.sh — tests for the pack hooks (hooks/pre-bash and its gates) and the helper scripts.
#
# Plain POSIX sh. Every test runs in temporary git repositories with a local bare remote (so
# origin/HEAD exists); nothing touches the network, the user's git config or this repository.
#
# Usage:
#   sh tests/run.sh                          scripts and hook run with sh
#   TEST_SH=bash bash tests/run.sh           ... with bash
#   TEST_SH=dash dash tests/run.sh           ... with dash
#
# Fake secrets are assembled at run time ("AKIA""...") so this file itself never matches the
# secrets pattern it tests.

set -u
set -f

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
TSH=${TEST_SH:-sh}
HOOK=$ROOT/hooks/pre-bash
TIER=$ROOT/scripts/risk-tier
SDDROOT=$ROOT/scripts/sdd-root
WORKSPACE=$ROOT/skills/implement/scripts/sdd-workspace
PACKAGE=$ROOT/skills/implement/scripts/review-package

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rsc-tests.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM

PASSES=0
FAILS=0

# Isolated git: no system or user config, a throwaway HOME.
HOME=$TMP/home
mkdir -p "$HOME"
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=$HOME/.gitconfig
export HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_PROJECT_DIR || :
git config --global user.name "Test Human"
git config --global user.email "human@example.com"
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global advice.detachedHead false
TMPDIR=$TMP/tmpdir
export TMPDIR
mkdir -p "$TMPDIR"

ok() { PASSES=$((PASSES + 1)); }
bad() {
  FAILS=$((FAILS + 1))
  printf 'FAIL: %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/    | /'; fi
}

# new_repo NAME [BRANCH] — $TMP/NAME on BRANCH (default feat/x) off main, with a bare remote and origin/HEAD.
new_repo() {
  _r=$TMP/$1
  git init -q --bare "$_r.git"
  git init -q "$_r"
  (
    cd "$_r" || exit 1
    printf '# demo\n' > README.md
    printf 'console.log(1)\n' > app.js
    git add README.md app.js
    git commit -q -m "chore: init"
    git remote add origin "$_r.git"
    git push -q origin main 2> /dev/null
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    git checkout -q -b "${2:-feat/x}"
  ) || { echo "setup failed for $1" >&2; exit 1; }
}

# put REPO PATH CONTENT — write a file (printf %s, so \n in CONTENT is literal) and commit it.
put() {
  mkdir -p "$(dirname -- "$TMP/$1/$2")"
  printf '%s\n' "$3" > "$TMP/$1/$2"
  git -C "$TMP/$1" add -- "$2"
  git -C "$TMP/$1" commit -q -m "feat: $2"
}

SECTIONS='Problem & why|Cost of not building it|The cheapest alternative|Goals|Non-goals / out of scope|Users & context|What the user can do|What result they get|What it must respect|How it proves it|Behaviour|Acceptance criteria|Points to clarify'

# write_spec REPO SLUG BRANCH [SKIP_SECTION] [EMPTY_SECTION] — an untracked spec under 02-DOCS.
write_spec() {
  _f=$TMP/$1/02-DOCS/wiki/sdd/specs/$2.md
  mkdir -p "$TMP/$1/02-DOCS/wiki/sdd/specs" "$TMP/$1/02-DOCS/wiki/sdd/progress"
  {
    printf '%s\n' '---' 'type: spec' "slug: $2" 'status: approved' "branch: $3" '---' '' '# Spec — demo' ''
    _old=$IFS
    IFS='|'
    for _s in $SECTIONS; do
      [ "$_s" = "${4:-}" ] && continue
      printf '## %s\n' "$_s"
      if [ "$_s" = "${5:-}" ]; then
        printf '%s\n' '<What concretely happens if nobody does this, and what it costs.' 'Required for specs dated 2026-09-06 or later.>' ''
      else
        printf 'Real content for %s.\n\n' "$_s"
      fi
    done
    IFS=$_old
  } > "$_f"
}

# progress REPO SLUG LINE... — write progress/<slug>.md with the given lines.
progress() {
  _f=$TMP/$1/02-DOCS/wiki/sdd/progress/$2.md
  mkdir -p "$(dirname -- "$_f")"
  shift 2
  printf '%s\n' "# Progress" "$@" > "$_f"
}

# json_str TEXT — TEXT as the inside of a JSON string.
json_str() {
  printf '%s' "$1" | awk '
    {
      out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\\") c = "\\\\"
        else if (c == "\"") c = "\\\""
        else if (c == "\t") c = "\\t"
        out = out c
      }
      if (NR > 1) printf "\\n"
      printf "%s", out
    }'
}

# payload CWD CMD [TOOL]
payload() {
  printf '{"session_id":"t1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s","description":"x"}}' \
    "$(json_str "$1")" "${3:-Bash}" "$(json_str "$2")"
}

# hook_raw DIR PAYLOAD [PATH] — run the hook from DIR; sets RC and ERR (stderr).
hook_raw() {
  if [ -n "${3:-}" ]; then
    ERR=$(cd "$1" && printf '%s' "$2" | PATH=$3 CLAUDE_PROJECT_DIR=$1 CLAUDE_PLUGIN_ROOT=$ROOT "$TSH_ABS" "$HOOK" 2>&1 > /dev/null)
  else
    ERR=$(cd "$1" && printf '%s' "$2" | CLAUDE_PROJECT_DIR=$1 CLAUDE_PLUGIN_ROOT=$ROOT "$TSH" "$HOOK" 2>&1 > /dev/null)
  fi
  RC=$?
}

# hook DIR CMD [TOOL] [PATH]
hook() { hook_raw "$1" "$(payload "$1" "$2" "${3:-Bash}")" "${4:-}"; }

# expect NAME RC [STDERR_ERE]
expect() {
  if [ "$RC" != "$2" ]; then
    bad "$1: exit $RC, want $2" "$ERR"
    return
  fi
  if [ -n "${3:-}" ] && ! printf '%s\n' "$ERR" | grep -qiE -- "$3"; then
    bad "$1: stderr does not match /$3/" "$ERR"
    return
  fi
  ok
}

# expect_clean NAME — exit 0 and nothing on stderr.
expect_clean() {
  if [ "$RC" != 0 ] || [ -n "$ERR" ]; then bad "$1: exit $RC, want 0 and no output" "$ERR"; else ok; fi
}

# expect_allow NAME — anything but a block (exit 2).
expect_allow() {
  if [ "$RC" = 2 ]; then bad "$1: blocked" "$ERR"; else ok; fi
}

# run_out NAME WANT_RC WANT_ERE CMD... — run a command, check its exit code and stdout.
run_out() {
  _n=$1 _rc=$2 _re=$3
  shift 3
  OUT=$("$@" 2>&1)
  RC=$?
  if [ "$RC" != "$_rc" ]; then bad "$_n: exit $RC, want $_rc" "$OUT"; return; fi
  if [ -n "$_re" ] && ! printf '%s\n' "$OUT" | grep -qE -- "$_re"; then bad "$_n: output does not match /$_re/" "$OUT"; return; fi
  ok
}

TSH_ABS=$(command -v "$TSH") || { echo "no shell $TSH" >&2; exit 1; }

# Fake secrets, assembled here so this file does not contain them.
AWS_KEY="AKIA""IOSFODNN7EXAMPLE"
GH_TOK="gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
PW_WORD="pass""word"

# ---------------------------------------------------------------------------------------------
# Syntax: sh -n on every script.
set +f
for f in "$HOOK" "$ROOT"/hooks/lib/*.sh "$ROOT/hooks/lib/sdd-root" "$ROOT/hooks/lib/risk-tier" \
  "$TIER" "$SDDROOT" "$WORKSPACE" "$PACKAGE" "$ROOT/skills/implement/scripts/task-brief" "$0"; do
  if [ -f "$f" ] && "$TSH" -n "$f" 2> /dev/null; then ok; else bad "syntax ($TSH -n): $f"; fi
done
set -f

# hooks.json: the shape marcsh accepts (one PreToolUse group on Bash running the dispatcher).
if command -v jq > /dev/null 2>&1; then
  _hj=$(jq -r '.hooks.PreToolUse[0] | "\(.matcher) \(.hooks[0].type) \(.hooks[0].command) \(.hooks[0].timeout)"' "$ROOT/hooks/hooks.json" 2>&1)
  if [ "$_hj" = 'Bash command sh "${CLAUDE_PLUGIN_ROOT}/hooks/pre-bash" 30' ]; then ok; else bad "hooks.json shape" "$_hj"; fi
fi

# ---------------------------------------------------------------------------------------------
# scripts/sdd-root
new_repo sr
mkdir -p "$TMP/sr/sub/deep"
run_out "sdd-root: none" 1 '' "$TSH" "$SDDROOT" "$TMP/sr"
[ -z "$OUT" ] && ok || bad "sdd-root: none prints nothing" "$OUT"
mkdir -p "$TMP/sr/02-DOCS"
_real=$(cd "$TMP/sr" && pwd -P)
run_out "sdd-root: at git root" 0 "^$_real\$" "$TSH" "$SDDROOT" "$TMP/sr"
run_out "sdd-root: from subdir" 0 "^$_real\$" sh -c "cd '$TMP/sr/sub/deep' && '$TSH' '$SDDROOT'"
rmdir "$TMP/sr/02-DOCS"
mkdir -p "$TMP/02-DOCS"
_tmpreal=$(cd "$TMP" && pwd -P)
run_out "sdd-root: above the git root" 0 "^$_tmpreal\$" "$TSH" "$SDDROOT" "$TMP/sr/sub"
rmdir "$TMP/02-DOCS"
_before=$(cd "$TMP/sr" && ls -aR)
"$TSH" "$SDDROOT" "$TMP/sr" > /dev/null 2>&1
[ "$_before" = "$(cd "$TMP/sr" && ls -aR)" ] && ok || bad "sdd-root: side-effect free"

# ---------------------------------------------------------------------------------------------
# scripts/risk-tier
new_repo rt
run_out "risk-tier: nothing to classify" 0 '^tier=none$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
put rt docs/guide.md "how to"
run_out "risk-tier: docs only is tier 0" 0 '^tier=0$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
put rt src/util.js "export const add = (a, b) => a + b"
run_out "risk-tier: code is tier 1" 0 '^tier=1$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
run_out "risk-tier: prints the base" 0 '^base=origin/main$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
put rt src/util.test.js "bcrypt.hash(x)"
run_out "risk-tier: auth signal in a test file is skipped" 0 '^tier=1$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
put rt src/notes.js "// we might use bcrypt later"
run_out "risk-tier: auth signal in a comment is skipped" 0 '^tier=1$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
run_out "risk-tier: --base" 0 '^tier=1$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER' --base main"
printf 'const k = 1\n' > "$TMP/rt/src/session.js"
run_out "risk-tier: untracked auth file counts" 0 '^reason=path auth: src/session.js$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER'"
run_out "risk-tier: --committed skips untracked work" 0 '^tier=1$' sh -c "cd '$TMP/rt' && '$TSH' '$TIER' --committed"
rm -f "$TMP/rt/src/session.js"

for case in "src/auth/handler.js|auth" ".env.local|secrets" ".github/workflows/ci.yml|ci" \
  "db/migrations/001.js|migrations" "src/billing/plan.js|billing" "CLAUDE.md|agent config" \
  "src/login.ts|auth" "certs/server.pem|secrets"; do
  _p=${case%%|*} _c=${case#*|}
  rm -rf "$TMP/rtp" "$TMP/rtp.git"
  new_repo rtp
  put rtp "$_p" "x = 1"
  run_out "risk-tier: path $_p is tier 2" 0 '^tier=2$' sh -c "cd '$TMP/rtp' && '$TSH' '$TIER'"
  run_out "risk-tier: path $_p reason" 0 "^reason=path $_c: $_p\$" sh -c "cd '$TMP/rtp' && '$TSH' '$TIER'"
done

for case in "src/a.js|const h = await bcrypt.hash(pw, 10)|auth" \
  "src/b.js|db.exec('ALTER TABLE users ADD COLUMN x int')|migrations" \
  "src/c.js|await stripe.paymentIntents.create({ amount })|billing" \
  "docs/d.md|key: $AWS_KEY|secrets"; do
  _p=${case%%|*} _rest=${case#*|}
  _l=${_rest%|*} _c=${_rest##*|}
  rm -rf "$TMP/rtc" "$TMP/rtc.git"
  new_repo rtc
  put rtc "$_p" "$_l"
  run_out "risk-tier: content $_c in $_p" 0 '^tier=2$' sh -c "cd '$TMP/rtc' && '$TSH' '$TIER'"
  run_out "risk-tier: content $_c reason" 0 "^reason=content $_c" sh -c "cd '$TMP/rtc' && '$TSH' '$TIER'"
done
run_out "risk-tier: never prints the secret" 0 '' sh -c "cd '$TMP/rtc' && '$TSH' '$TIER'"
case $OUT in *"$AWS_KEY"*) bad "risk-tier printed the secret" "$OUT" ;; *) ok ;; esac

# Fallback without origin/HEAD: a lone repo on master.
git init -q "$TMP/lone"
(cd "$TMP/lone" && git checkout -q -b master && printf 'x\n' > a.txt && git add a.txt && git commit -q -m init \
  && git checkout -q -b topic && printf 'y\n' > b.js && git add b.js && git commit -q -m b)
run_out "risk-tier: falls back to master" 0 '^base=master$' sh -c "cd '$TMP/lone' && '$TSH' '$TIER'"
git init -q "$TMP/nodefault"
(cd "$TMP/nodefault" && git checkout -q -b trunk && printf 'x\n' > a.txt && git add a.txt && git commit -q -m init)
run_out "risk-tier: no default branch is an error" 1 'default branch' sh -c "cd '$TMP/nodefault' && '$TSH' '$TIER'"
run_out "risk-tier: not a repository" 1 'not a git repository' sh -c "cd '$TMP/tmpdir' && '$TSH' '$TIER'"

# ---------------------------------------------------------------------------------------------
# hooks/pre-bash: plain commands, parsing.
new_repo h
hook "$TMP/h" "ls -la"
expect_clean "plain command"
hook "$TMP/h" "git status && git log --oneline -3"
expect_clean "git read commands"
hook "$TMP/h" 'echo "git push" && git log --grep "gh pr merge"'
expect_clean "git push inside a string is not a command"
hook_raw "$TMP/h" 'not json {'
expect_allow "unparsable payload"
hook_raw "$TMP/h" '{"tool_input": {"command": "git push'
expect_allow "truncated payload"
hook_raw "$TMP/h" '{"tool_name":"Bash","tool_input":{}}'
expect_clean "payload without a command"

# Tier-2 work on h (an auth path), no 02-DOCS yet.
put h src/auth/login.js "export const login = () => 1"
hook "$TMP/h" "git push origin feat/x"
expect_clean "tier-2 push without 02-DOCS is allowed"
hook "$TMP/h" "gh pr merge 3"
expect_clean "tier-2 merge without 02-DOCS is allowed"

mkdir -p "$TMP/h/02-DOCS/wiki/sdd/specs"
hook "$TMP/h" "git push origin feat/x"
expect "tier-2 push without a spec" 2 'branch: feat/x'
hook "$TMP/h" "git push origin feat/x"
expect "tier-2 push names the reason" 2 'auth: src/auth/login.js'
hook "$TMP/h" "gh pr create --fill"
expect "tier-2 gh pr create without a spec" 2 'no spec'
mkdir -p "$TMP/other"
hook "$TMP/other" "git -C '$TMP/h' push"
expect "git -C dir push" 2 'branch: feat/x'
hook "$TMP/other" "cd '$TMP/h' && git push"
expect "cd dir && git push" 2 'branch: feat/x'
hook "$TMP/h" "FOO=1 GIT_TRACE=0 git push -u origin HEAD"
expect "env prefix" 2 'branch: feat/x'
hook "$TMP/h" "npm test && git push || echo failed"
expect "chained push" 2 'branch: feat/x'
hook "$TMP/h" "sh -c 'git push'"
expect "sh -c push" 2 'branch: feat/x'
hook "$TMP/h" "git push" "bg_start"
expect "bg_start push" 2 'branch: feat/x'
hook "$TMP/h" "git push --dry-run"
expect_clean "dry-run push"

write_spec h login feat/x "Goals" "Cost of not building it"
hook "$TMP/h" "git push"
expect "failing spec: missing section" 2 'missing section\(s\): Goals'
hook "$TMP/h" "git push"
expect "failing spec: empty section" 2 'empty section\(s\): Cost of not building it'
write_spec h login feat/x
hook "$TMP/h" "git push"
expect "passing spec without a panel record" 2 'panel correctness, security, tests'
progress h login '## Review rounds' '- T1: round 1'
hook "$TMP/h" "git push"
expect "progress without a panel record" 2 'progress/login.md'
progress h login '## Review rounds' '- T1: round 1' '- T1: panel correctness, security, tests'
hook "$TMP/h" "git push"
expect_clean "passing spec and panel record"
hook "$TMP/h" "gh pr create --fill"
expect_clean "gh pr create with spec and panel"
write_spec h login feat/other
hook "$TMP/h" "git push"
expect "spec linked to another branch" 2 'branch: feat/x'
write_spec h login feat/x

# Tier-2 merge.
hook "$TMP/h" "gh pr merge --squash"
expect "gh pr merge at tier 2" 2 'human merges'
hook "$TMP/h" "gh pr merge 12 --auto"
expect "gh pr merge <n> at tier 2" 2 'human merges'
git -C "$TMP/h" checkout -q main
hook "$TMP/h" "git merge --no-ff feat/x"
expect "git merge tier-2 branch into main" 2 'human merges'
hook "$TMP/h" "git merge --abort"
expect_clean "git merge --abort"
hook "$TMP/h" "git merge origin/main"
expect_clean "git merge of the default itself"
git -C "$TMP/h" checkout -q feat/x
hook "$TMP/h" "git merge main"
expect_clean "git merge main into the feature branch"

# Tier 1: no spec needed, the decision queue still gates gh pr merge.
new_repo q
put q src/util.js "export const one = 1"
mkdir -p "$TMP/q/02-DOCS/wiki/sdd/specs"
hook "$TMP/q" "git push"
expect_clean "tier-1 push without a spec"
hook "$TMP/q" "gh pr merge --squash"
expect_clean "tier-1 merge without a queue"
write_spec q util feat/x
progress q util '## Decision queue' '- [review-after] Q1 — assumed UTC, spec, T1' '- [blocking] Q2 — pick the rounding rule, T2 failed, T2' '' '## Review rounds' '- T1: round 1'
hook "$TMP/q" "gh pr merge --squash"
expect "blocking decision queue" 2 'Q2'
progress q util '## Decision queue' '- [review-after] Q1 — assumed UTC, spec, T1' '' '## Notes' '- [blocking] not in the queue section'
hook "$TMP/q" "gh pr merge --squash"
expect_clean "review-after items do not block"
git -C "$TMP/q" checkout -q main
hook "$TMP/q" "git merge feat/x"
expect_clean "git merge of a tier-1 branch into main"
git -C "$TMP/q" checkout -q feat/x

# ---------------------------------------------------------------------------------------------
# Authorship.
new_repo a
hook "$TMP/a" 'git commit -m "fix: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"'
expect "commit with an AI co-author" 2 'co-author'
hook "$TMP/a" "git commit -m \"\$(cat <<'EOF'
feat: add thing

Body text.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)\""
expect "commit with a generated-with footer" 2 'generated'
hook "$TMP/a" "git commit -am 'fix: y

Co-authored-by: GitHub Copilot <copilot@github.com>'"
expect "commit -am with an AI co-author" 2 'co-author'
hook "$TMP/a" 'git commit --trailer "Co-authored-by: Claude <noreply@anthropic.com>" -m "fix"'
expect "commit --trailer with an AI co-author" 2 'co-author'
hook "$TMP/a" "git commit -F - <<'EOF'
fix: z

Co-Authored-By: Claude <noreply@anthropic.com>
EOF"
expect "commit -F - heredoc" 2 'co-author'
printf 'fix: w\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$TMP/a/msg.txt"
hook "$TMP/a" "git commit -F msg.txt"
expect "commit -F file" 2 'co-author'
hook "$TMP/a" 'git commit -m "fix: x" -m "Co-Authored-By: Jane Doe <jane@gmail.com>"'
expect_clean "commit with a human co-author"
hook "$TMP/a" 'git commit -m "feat: explain the claude engine timeouts"'
expect_clean "commit mentioning claude in the subject"
put a src/ok.js "export const ok = 1"
hook "$TMP/a" "git push"
expect_clean "push of clean commits"
printf 'x\n' > "$TMP/a/src/ai.js"
git -C "$TMP/a" add src/ai.js
git -C "$TMP/a" commit -q -m "feat: ai" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
hook "$TMP/a" "git push"
expect "push of a commit with an AI trailer" 2 'origin/main\.\.HEAD'
git -C "$TMP/a" reset -q --hard HEAD~1

# ---------------------------------------------------------------------------------------------
# Secrets.
new_repo s
mkdir -p "$TMP/s/src"
printf 'const k = "%s"\n' "$AWS_KEY" > "$TMP/s/src/aws.js"
git -C "$TMP/s" add src/aws.js
hook "$TMP/s" 'git commit -m "feat: aws"'
expect "commit with a staged AWS key" 2 'secret'
case $ERR in *"$AWS_KEY"*) bad "secrets gate printed the secret" "$ERR" ;; *) ok ;; esac
git -C "$TMP/s" reset -q
rm -f "$TMP/s/src/aws.js"
printf 'db_%s = "hunter2hunter2"\n' "$PW_WORD" > "$TMP/s/src/db.py"
git -C "$TMP/s" add src/db.py
hook "$TMP/s" 'git commit -m "feat: db"'
expect "commit with a hard-coded password" 2 'src/db.py'
printf 'db_%s = "hunter2hunter2"  # gitleaks:allow\n' "$PW_WORD" > "$TMP/s/src/db.py"
git -C "$TMP/s" add src/db.py
hook "$TMP/s" 'git commit -m "feat: db"'
expect_clean "allow marker skips the line"
printf 'db_%s = os.environ["DB_PASS"]\ntoken = get_token()\n' "$PW_WORD" > "$TMP/s/src/db.py"
git -C "$TMP/s" add src/db.py
hook "$TMP/s" 'git commit -m "feat: db"'
expect_clean "commit reading a secret from the environment"
git -C "$TMP/s" commit -q -m "feat: db"
printf 'export const t = "%s"\n' "$GH_TOK" > "$TMP/s/src/gh.js"
hook "$TMP/s" 'git commit -am "feat: gh"'
expect_clean "commit -a with an untracked file is not scanned"
git -C "$TMP/s" add src/gh.js
git -C "$TMP/s" commit -q -m "feat: gh"
hook "$TMP/s" "git push"
expect "push of a branch with a GitHub token" 2 'src/gh.js'
printf 'export const t = 1\n' > "$TMP/s/src/gh.js"
hook "$TMP/s" 'git commit -am "fix: drop token"'
expect_clean "commit -a removing the secret"

# ---------------------------------------------------------------------------------------------
# Without jq: the awk payload parser.
NOJQ=$TMP/nojq-bin
mkdir -p "$NOJQ"
for t in sh "$TSH" awk sed grep git cat dirname basename tr cksum sort head wc ls mkdir rm env uname expr printf test cut; do
  _p=$(command -v "$t" 2> /dev/null) || continue
  case $_p in /*) ln -sf "$_p" "$NOJQ/$t" ;; esac
done
if PATH=$NOJQ command -v jq > /dev/null 2>&1; then bad "no-jq PATH still has jq"; else ok; fi
hook "$TMP/h" "git push origin feat/x" Bash "$NOJQ"
expect_clean "no jq: passing tier-2 push"
rm -f "$TMP/h/02-DOCS/wiki/sdd/progress/login.md"
hook "$TMP/h" "git push origin feat/x" Bash "$NOJQ"
expect "no jq: tier-2 push without a panel" 2 'panel correctness'
hook "$TMP/a" 'git commit -m "say \"hi\" \\ there" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' Bash "$NOJQ"
expect "no jq: escaped quotes" 2 'co-author'
hook_raw "$TMP/a" '{"cwd":"'"$TMP/a"'","tool_name":"Bash","tool_input":{"description":"\"command\": \"git push\"","command":"git commit -m \"x\n\n🤖 Generated with tool\""}}' "$NOJQ"
expect "no jq: unicode escapes and a decoy key" 2 'generated'
hook_raw "$TMP/a" '{"tool_input":{"command":"ls -la"}}' "$NOJQ"
expect_clean "no jq: plain command"
hook_raw "$TMP/a" '{"tool_input": {"command": "git push' "$NOJQ"
expect_allow "no jq: truncated payload"

# ---------------------------------------------------------------------------------------------
# implement/scripts fixes.
new_repo rp
put rp src/one.js "export const one = 1"
git -C "$TMP/rp" config color.ui always
git -C "$TMP/rp" config diff.external "$TMP/ext-diff"
printf '#!/bin/sh\necho EXTERNAL-DIFF\n' > "$TMP/ext-diff"
chmod +x "$TMP/ext-diff"
_pkg=$(cd "$TMP/rp" && "$TSH" "$PACKAGE" main HEAD 2> /dev/null)
if [ -f "$_pkg" ] && ! grep -q "$(printf '\033')" "$_pkg" && ! grep -q EXTERNAL-DIFF "$_pkg" && grep -q '^+export const one' "$_pkg"; then ok; else bad "review-package: plain diff despite color.ui and diff.external" "$(cat "$_pkg" 2> /dev/null)"; fi

new_repo w1
new_repo w2
_w1=$(cd "$TMP/w1" && "$TSH" "$WORKSPACE")
_w2=$(cd "$TMP/w2" && "$TSH" "$WORKSPACE")
mkdir -p "$TMP/w1/sub"
_w1b=$(cd "$TMP/w1/sub" && "$TSH" "$WORKSPACE")
case $_w1 in "$TMPDIR"/rsc-sdd-scratch-*) ok ;; *) bad "sdd-workspace: fallback under TMPDIR with a project suffix" "$_w1" ;; esac
[ "$_w1" != "$_w2" ] && ok || bad "sdd-workspace: two projects get two dirs" "$_w1 / $_w2"
[ "$_w1" = "$_w1b" ] && ok || bad "sdd-workspace: same project, same dir" "$_w1 / $_w1b"

# ---------------------------------------------------------------------------------------------
printf '%s: %d passed, %d failed\n' "$TSH" "$PASSES" "$FAILS"
[ "$FAILS" = 0 ]
