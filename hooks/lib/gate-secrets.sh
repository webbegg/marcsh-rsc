# hooks/lib/gate-secrets.sh — secrets gate (git commit, git push). Sourced by pre-bash after
# rsc_context.
#
# Blocks when the added lines of the staged diff (commit; the whole diff against HEAD with -a or
# paths) or of <default>...<pushed ref> (push) hold a secret, by secrets.awk (concrete key formats,
# and literal values assigned to password/secret/token/api-key names; see that file). Applies in
# every repository, with or without 02-DOCS. The message names the file and the kind, never the
# value. On error the check is skipped: allow.

# gate_secrets_commit WIDE
gate_secrets_commit() {
  if [ "$1" = 1 ] && [ -n "$RSC_BRANCH" ]; then
    _gs_hits=$(rsc_diff "$RSC_TOP" -U0 --no-renames HEAD 2> /dev/null | awk -f "$LIB/secrets.awk") && return 0
  else
    _gs_hits=$(rsc_diff "$RSC_TOP" -U0 --no-renames --cached 2> /dev/null | awk -f "$LIB/secrets.awk") && return 0
  fi
  block "git commit: the changes being committed look like they hold a secret ($_gs_hits). Remove it and load it from the environment; mark a deliberate fake with gitleaks:allow on its line."
}

# gate_secrets_push [SRC] [WHAT] — the commits SRC (default HEAD) adds to the default branch.
gate_secrets_push() {
  [ "$RSC_HAS_DEFAULT" = 1 ] || return 0 # gate_authorship_push already noted it
  _gs_src=${1:-HEAD}
  _gs_hits=$(rsc_diff "$RSC_TOP" -U0 --no-renames "$RSC_DEFAULT_REF...$_gs_src" 2> /dev/null | awk -f "$LIB/secrets.awk") && return 0
  block "${2:-git push}: the branch diff $RSC_DEFAULT_REF...$_gs_src looks like it holds a secret ($_gs_hits). Remove it from the history before pushing, and rotate it if it was ever pushed."
}
