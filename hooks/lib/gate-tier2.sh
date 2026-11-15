# hooks/lib/gate-tier2.sh — the tier-2 gates (git push, gh pr create, gh pr merge, git merge into
# the default branch) and the decision-queue gate (gh pr merge). Sourced by pre-bash after
# rsc_context, so RSC_TOP, RSC_BRANCH, RSC_DEFAULT_*, RSC_ROOT and the RSC_HAS_* flags are set.
#
# All of them apply only inside an SDD workspace (02-DOCS found by rsc_sdd_root); without one
# they allow. The tier is risk-tier's, on the committed diff (what leaves the machine).
#
# Errors: when the tier cannot be computed (no default branch, no common history) the gates allow
# with a note, as every check does. Once the tier IS 2, blocking is the documented safe default
# (skills/asdd/references/without-rsc-cli.md §1: "at tier 2, do not push, open a PR or merge until
# the spec exists, the three lenses ran and the user said yes"): a missing, unreadable or failing
# spec or progress file blocks.

PANEL_LINE='panel correctness, security, tests'

# rsc_tier BASE HEAD — sets RSC_TIER and RSC_TIER_WHY (at most 5 reasons, `; `-joined), or
# returns 1 with RSC_TIER_ERR.
rsc_tier() {
  RSC_TIER=''
  RSC_TIER_WHY=''
  RSC_TIER_ERR=''
  _rt_out=$(rsc_risk_tier "$RSC_TOP" "$1" "$2" 1 2>&1) || {
    RSC_TIER_ERR=${_rt_out%%
*}
    return 1
  }
  _rt_n=0
  while IFS= read -r _rt_line; do
    case $_rt_line in
      tier=*) RSC_TIER=${_rt_line#tier=} ;;
      reason=*)
        _rt_n=$((_rt_n + 1))
        [ "$_rt_n" -le 5 ] || continue
        _rt_line=${_rt_line#reason=}
        _rt_line=${_rt_line#path }
        RSC_TIER_WHY=${RSC_TIER_WHY:+$RSC_TIER_WHY; }$_rt_line
        ;;
    esac
  done << EOF
$_rt_out
EOF
  [ "$_rt_n" -le 5 ] || RSC_TIER_WHY="$RSC_TIER_WHY; ..."
  return 0
}

# rsc_specs_for BRANCH — spec-check.awk's PASS/FAIL lines for the specs whose frontmatter names
# BRANCH, under $RSC_ROOT/02-DOCS/wiki/sdd/specs.
rsc_specs_for() {
  _sf_branch=$1
  [ -n "$_sf_branch" ] || return 0
  set -- "$RSC_ROOT/02-DOCS/wiki/sdd/specs"/*.md
  [ -f "$1" ] || return 0
  awk -v want="$_sf_branch" -f "$LIB/spec-check.awk" "$@"
}

# rsc_has_panel FILE — FILE has the panel record line of without-rsc-cli.md §3:
# `<task>: panel correctness, security, tests` (optionally as a list item).
rsc_has_panel() {
  [ -f "$1" ] && grep -qE "^[[:space:]]*([-*][[:space:]]+)?[^[:space:]:]+: $PANEL_LINE[[:space:]]*\$" "$1"
}

# rsc_target_branch DIR TARGET — TARGET when it names a local branch, else the current branch.
rsc_target_branch() {
  if [ -n "$2" ] && git -C "$1" rev-parse -q --verify "refs/heads/$2" > /dev/null 2>&1; then
    printf '%s\n' "$2"
  else
    printf '%s\n' "$RSC_BRANCH"
  fi
}

# gate_spec_panel WHAT — tier-2 push / PR gate.
gate_spec_panel() {
  [ "$RSC_HAS_ROOT" = 1 ] || return 0
  if [ "$RSC_HAS_DEFAULT" != 1 ]; then
    note "$1: no default branch (origin/HEAD, main or master); the tier-2 spec and panel gate did not run"
    return 0
  fi
  if ! rsc_tier "$RSC_DEFAULT_REF" HEAD; then
    note "$1: risk tier unknown ($RSC_TIER_ERR); the tier-2 spec and panel gate did not run"
    return 0
  fi
  [ "$RSC_TIER" = 2 ] || return 0
  _sp_specs=$(rsc_specs_for "$RSC_BRANCH")
  if [ -z "$_sp_specs" ]; then
    block "$1: tier-2 change ($RSC_TIER_WHY) and no spec in 02-DOCS/wiki/sdd/specs/ has \`branch: ${RSC_BRANCH:-<detached HEAD>}\` in its frontmatter. Write and approve the spec (specify), add that line, record the three-lens panel, then retry."
    return 0
  fi
  _sp_missing=''
  while IFS=$TAB read -r _sp_res _sp_file _sp_msg; do
    [ -n "$_sp_file" ] || continue
    _sp_slug=${_sp_file##*/}
    _sp_slug=${_sp_slug%.md}
    if [ "$_sp_res" = PASS ]; then
      rsc_has_panel "$RSC_ROOT/02-DOCS/wiki/sdd/progress/$_sp_slug.md" && return 0
      _sp_missing="$_sp_missing; 02-DOCS/wiki/sdd/progress/$_sp_slug.md has no panel record line \`<task>: $PANEL_LINE\` (run the three-lens review, then append it under ## Review rounds)"
    else
      _sp_missing="$_sp_missing; spec gate $_sp_msg"
    fi
  done << EOF
$_sp_specs
EOF
  block "$1: tier-2 change ($RSC_TIER_WHY) on branch ${RSC_BRANCH:-<detached HEAD>} is not ready${_sp_missing}."
}

# gate_pr_merge DIR TARGET — `gh pr merge` at tier 2: never by an agent.
gate_pr_merge() {
  [ "$RSC_HAS_ROOT" = 1 ] || return 0
  if [ "$RSC_HAS_DEFAULT" != 1 ]; then
    note "gh pr merge: no default branch (origin/HEAD, main or master); the tier-2 merge gate did not run"
    return 0
  fi
  _pm_head=HEAD
  if [ -n "$2" ] && git -C "$1" rev-parse -q --verify "refs/heads/$2" > /dev/null 2>&1; then
    _pm_head=$2
  elif [ -n "$2" ] && [ "$RSC_BRANCH" = "$RSC_DEFAULT_NAME" ]; then
    note "gh pr merge $2: run from the default branch, the PR's tier cannot be computed offline; the tier-2 merge gate did not run"
    return 0
  fi
  if ! rsc_tier "$RSC_DEFAULT_REF" "$_pm_head"; then
    note "gh pr merge: risk tier unknown ($RSC_TIER_ERR); the tier-2 merge gate did not run"
    return 0
  fi
  [ "$RSC_TIER" = 2 ] || return 0
  block "gh pr merge: tier-2 change ($RSC_TIER_WHY). The human merges this in the forge, after approving it; an agent never merges tier 2 (ship skill)."
}

# gate_git_merge DIR TARGET — `git merge TARGET` while on the default branch, at tier 2.
gate_git_merge() {
  [ "$RSC_HAS_ROOT" = 1 ] && [ "$RSC_HAS_DEFAULT" = 1 ] || return 0
  [ "$RSC_BRANCH" = "$RSC_DEFAULT_NAME" ] || return 0
  case $2 in
    "$RSC_DEFAULT_REF" | "origin/$RSC_DEFAULT_NAME" | "$RSC_DEFAULT_NAME" | FETCH_HEAD | HEAD | -) return 0 ;;
  esac
  if ! rsc_tier HEAD "$2"; then
    # Not a commit (git merge itself will refuse) or no shared history: nothing to gate.
    return 0
  fi
  [ "$RSC_TIER" = 2 ] || return 0
  block "git merge $2 into $RSC_DEFAULT_NAME: tier-2 change ($RSC_TIER_WHY). The human merges this in the forge, after approving it; an agent never merges tier 2 (ship skill)."
}

# gate_queue DIR TARGET — `gh pr merge` while the decision queue has `- [blocking]` items
# (the `## Decision queue` of progress/<slug>.md, for each spec linked to the branch).
gate_queue() {
  [ "$RSC_HAS_ROOT" = 1 ] || return 0
  _dq_specs=$(rsc_specs_for "$(rsc_target_branch "$1" "$2")")
  [ -n "$_dq_specs" ] || return 0
  _dq_found=''
  while IFS=$TAB read -r _dq_res _dq_file _dq_msg; do
    [ -n "$_dq_file" ] || continue
    _dq_slug=${_dq_file##*/}
    _dq_slug=${_dq_slug%.md}
    _dq_pf=$RSC_ROOT/02-DOCS/wiki/sdd/progress/$_dq_slug.md
    [ -f "$_dq_pf" ] || continue
    _dq_items=$(awk '
      /^##?[ \t]/ { inq = (tolower($0) ~ /^##[ \t]+decision queue[ \t]*$/); next }
      inq && /^[ \t]*- \[blocking\]/ { sub(/^[ \t]*- /, ""); n++; if (n <= 5) out = out (n > 1 ? "; " : "") $0 }
      END { if (n) { print out (n > 5 ? "; ..." : ""); exit 3 } }
    ' "$_dq_pf") && continue
    _dq_found="$_dq_found; progress/$_dq_slug.md: $_dq_items"
  done << EOF
$_dq_specs
EOF
  [ -n "$_dq_found" ] || return 0
  block "gh pr merge: the decision queue still has blocking items${_dq_found}. They stop a merge until the human answers them."
}
