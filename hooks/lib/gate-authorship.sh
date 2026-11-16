# hooks/lib/gate-authorship.sh — authorship gate (git commit, git push). Sourced by pre-bash
# after rsc_context.
#
# Blocks a commit message that credits an AI (an AI Co-Authored-By trailer, a "Generated with"
# footer, the robot emoji): skills/ship/SKILL.md, "The hard rule" (msg-check.awk has the exact
# patterns). Applies in every repository, with or without 02-DOCS. A visible -m / --trailer /
# `-F -` here-document is checked by parse-command.awk (the `commit-bad` action, reported by
# pre-bash); this file checks a -F message file and, on push, every commit in <default>..HEAD.
# A message typed in the editor is not visible to a PreToolUse hook; the push check catches it.
# On error (no default branch, unreadable file) the check is skipped with a note: allow.

# gate_authorship_file DIR FILE — `git commit -F FILE`.
gate_authorship_file() {
  [ -n "$2" ] || return 0
  case $2 in
    /*) _ga_f=$2 ;;
    *) _ga_f=$1/$2 ;;
  esac
  if [ ! -f "$_ga_f" ] || [ ! -r "$_ga_f" ]; then
    note "git commit -F $2: cannot read the message file; authorship not checked"
    return 0
  fi
  _ga_r=$(awk -f "$LIB/msg-check.awk" -f "$LIB/msg-scan.awk" < "$_ga_f") && return 0
  block "git commit: the message file $2 credits an AI ($_ga_r). Commits ship under the responsible person's name only (ship skill, the hard rule); remove that line and commit again."
}

# gate_authorship_push — `git push`: the messages of <default>..HEAD.
gate_authorship_push() {
  if [ "$RSC_HAS_DEFAULT" != 1 ]; then
    note "git push: no default branch (origin/HEAD, main or master) in $RSC_TOP; authorship and secrets not checked. Fix: git remote set-head origin -a"
    return 0
  fi
  _ga_r=$(rsc_git "$RSC_TOP" log --format=%B "$RSC_DEFAULT_REF..HEAD" 2> /dev/null | awk -f "$LIB/msg-check.awk" -f "$LIB/msg-scan.awk") && return 0
  block "git push: a commit in $RSC_DEFAULT_REF..HEAD credits an AI ($_ga_r). Commits ship under the responsible person's name only (ship skill, the hard rule); strip it (git commit --amend, or git rebase -i $RSC_DEFAULT_REF) and push again."
}
