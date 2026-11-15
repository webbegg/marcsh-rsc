# hooks/lib/gate-tier2.sh — the push gates (every git push refspec: authorship, secrets, and the
# tier-2 spec + panel gate, or the merge gate when it lands on the default branch), the tier-2
# gates of gh pr create, gh pr merge and git merge into the default branch, and the decision-queue
# gate (gh pr merge). Sourced by pre-bash after rsc_context, so RSC_TOP, RSC_BRANCH,
# RSC_DEFAULT_*, RSC_ROOT and the RSC_HAS_* flags are set.
#
# The tier gates apply only inside an SDD workspace (02-DOCS found by rsc_sdd_root); without one
# they allow. The tier is risk-tier's, on the committed diff of what is pushed (the source of each
# refspec, not HEAD) against the default branch: what leaves the machine.
#
# Errors: when the tier cannot be computed (no default branch, no common history) the gates allow
# with a note, as every check does. Once the tier IS 2, blocking is the documented safe default
# (skills/asdd/references/without-rsc-cli.md §1: "at tier 2, do not push, open a PR or merge until
# the spec exists, the three lenses ran and the user said yes"): a missing, unreadable or failing
# spec or progress file blocks.

PANEL_LINE='panel correctness, security, tests'
MAX_PUSHED=20
NL='
'
# Caches for one hook run, newline-separated lines starting with "<RSC_TOP> <key>" and a tab:
_RT_CACHE=$NL # rsc_tier: rc, tier, reasons or error
_RV_CACHE=$NL # rsc_rev: commit, local branch name
_GP_DONE=$NL  # gate_push_commits: commits already checked (and passed)
_GP_N=0       # distinct commits checked

# rsc_cached CACHE KEY — sets RSC_CACHED to the value stored for KEY, or returns 1.
rsc_cached() {
  case $1 in
    *"$NL$2$TAB"*)
      RSC_CACHED=${1#*"$NL$2$TAB"}
      RSC_CACHED=${RSC_CACHED%%"$NL"*}
      return 0
      ;;
  esac
  return 1
}

# rsc_tier BASE HEAD — sets RSC_TIER and RSC_TIER_WHY (at most 5 reasons, `; `-joined), or
# returns 1 with RSC_TIER_ERR. Cached per BASE HEAD.
rsc_tier() {
  RSC_TIER=''
  RSC_TIER_WHY=''
  RSC_TIER_ERR=''
  if rsc_cached "$_RT_CACHE" "$RSC_TOP $1 $2"; then
    RSC_TIER=${RSC_CACHED#?"$TAB"}
    RSC_TIER_WHY=${RSC_TIER#*"$TAB"}
    RSC_TIER=${RSC_TIER%%"$TAB"*}
    case $RSC_CACHED in 1*) RSC_TIER_ERR=$RSC_TIER_WHY; return 1 ;; esac
    return 0
  fi
  if _rt_out=$(rsc_risk_tier "$RSC_TOP" "$1" "$2" 1 2>&1); then
    rsc_tier_store "$1" "$2" "$_rt_out"
    return 0
  fi
  RSC_TIER_ERR=${_rt_out%%
*}
  _RT_CACHE="$_RT_CACHE$RSC_TOP $1 $2${TAB}1$TAB$TAB$RSC_TIER_ERR$NL"
  return 1
}

# rsc_tier_store BASE HEAD OUT — parses risk-tier's output OUT into RSC_TIER and RSC_TIER_WHY and
# caches them for BASE HEAD.
rsc_tier_store() {
  RSC_TIER=''
  RSC_TIER_WHY=''
  RSC_TIER_ERR=''
  _rt_out=$3
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
  _RT_CACHE="$_RT_CACHE$RSC_TOP $1 $2${TAB}0$TAB$RSC_TIER$TAB$RSC_TIER_WHY$NL"
  return 0
}

# rsc_rev SRC — sets RSC_REV_OID (the commit SRC names; empty when it names none) and
# RSC_REV_NAME (its local branch name, or empty). One git call, cached per SRC.
rsc_rev() {
  if rsc_cached "$_RV_CACHE" "$RSC_TOP $1"; then
    RSC_REV_OID=${RSC_CACHED%%"$TAB"*}
    RSC_REV_NAME=${RSC_CACHED#*"$TAB"}
    return 0
  fi
  RSC_REV_OID=''
  RSC_REV_NAME=''
  _rv_out=$(git -C "$RSC_TOP" rev-parse "$1^{commit}" --symbolic-full-name "$1" -- 2> /dev/null) || _rv_out=''
  while IFS= read -r _rv_line; do
    case $_rv_line in
      refs/heads/?*) RSC_REV_NAME=${_rv_line#refs/heads/} ;;
      *[!0-9a-f]* | '') ;;
      *) [ -n "$RSC_REV_OID" ] || RSC_REV_OID=$_rv_line ;;
    esac
  done << EOF
$_rv_out
EOF
  _RV_CACHE="$_RV_CACHE$RSC_TOP $1$TAB$RSC_REV_OID$TAB$RSC_REV_NAME$NL"
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
# `<task>: panel correctness, security, tests` (optionally as a list item), outside code fences.
rsc_has_panel() {
  [ -f "$1" ] && awk -v want="$PANEL_LINE" '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      l = $0
      sub(/^[ \t]*([-*][ \t]+)?/, "", l)
      sub(/[ \t]+$/, "", l)
      i = index(l, ": ")
      if (i > 1 && substr(l, 1, i - 1) !~ /[ \t:]/ && substr(l, i + 2) == want) { found = 1; exit }
    }
    END { exit !found }
  ' "$1"
}

# rsc_target_branch DIR TARGET — TARGET when it names a local branch, else the current branch.
rsc_target_branch() {
  if [ -n "$2" ] && git -C "$1" rev-parse -q --verify "refs/heads/$2" > /dev/null 2>&1; then
    printf '%s\n' "$2"
  else
    printf '%s\n' "$RSC_BRANCH"
  fi
}

# gate_spec_panel WHAT SRC BRANCH [ALT] — tier-2 push / PR gate for the commits of SRC, which the
# forge sees as branch BRANCH (empty: detached HEAD). The spec is the one linked to BRANCH, else
# to ALT (the local branch name of SRC).
gate_spec_panel() {
  [ "$RSC_HAS_ROOT" = 1 ] || return 0
  _sp_what=$1 _sp_src=${2:-HEAD} _sp_name=$3 _sp_alt=${4:-}
  if [ "$RSC_HAS_DEFAULT" != 1 ]; then
    note "$_sp_what: no default branch (origin/HEAD, main or master); the tier-2 spec and panel gate did not run"
    return 0
  fi
  if ! rsc_tier "$RSC_DEFAULT_REF" "$_sp_src"; then
    note "$_sp_what: risk tier unknown ($RSC_TIER_ERR); the tier-2 spec and panel gate did not run"
    return 0
  fi
  [ "$RSC_TIER" = 2 ] || return 0
  _sp_specs=$(rsc_specs_for "$_sp_name")
  if [ -z "$_sp_specs" ] && [ -n "$_sp_alt" ] && [ "$_sp_alt" != "$_sp_name" ]; then
    _sp_specs=$(rsc_specs_for "$_sp_alt")
  fi
  if [ -z "$_sp_specs" ]; then
    block "$_sp_what: tier-2 change ($RSC_TIER_WHY) and no spec in 02-DOCS/wiki/sdd/specs/ has \`branch: ${_sp_name:-<detached HEAD>}\` in its frontmatter. Write and approve the spec (specify), add that line, record the three-lens panel, then retry."
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
  block "$_sp_what: tier-2 change ($RSC_TIER_WHY) on branch ${_sp_name:-<detached HEAD>} is not ready${_sp_missing}."
}

# gate_push DIR SRC DST [LABEL] — one pushed refspec (parse-command.awk's push line): authorship
# and secrets of the commits SRC adds to the default branch, then the merge gate when DST is the
# default branch (pushing onto it is a merge), else the tier-2 spec + panel gate for branch DST.
# The commits of one source are checked once (gate_push_commits); stops at the first block.
gate_push() {
  [ -z "$BLOCKS" ] || return 0
  _gp_src=$2 _gp_dst=$3 _gp_what=${4:-}
  case $_gp_src in '' | -*) return 0 ;; @) _gp_src=HEAD ;; esac
  case $_gp_dst in -*) return 0 ;; esac
  if [ -z "$_gp_what" ]; then
    if [ "$_gp_dst" = @push ]; then _gp_what="git push"; else _gp_what="git push $_gp_src${_gp_dst:+:$_gp_dst}"; fi
  fi
  rsc_rev "$_gp_src"
  _gp_rev=$RSC_REV_OID
  case $_gp_src in
    HEAD) _gp_sname=$RSC_BRANCH ;;
    refs/heads/*) _gp_sname=${_gp_src#refs/heads/} ;;
    *) _gp_sname=$RSC_REV_NAME ;;
  esac
  case $_gp_dst in
    @push)
      # Where a plain `git push` goes (push.default, the upstream), else the current branch.
      _gp_dst=$(git -C "$RSC_TOP" rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2> /dev/null) || _gp_dst=''
      case $_gp_dst in */*) _gp_dst=${_gp_dst#*/} ;; *) _gp_dst=$RSC_BRANCH ;; esac
      ;;
    '')
      case $_gp_src in
        HEAD) _gp_dst=$RSC_BRANCH ;;
        *) _gp_dst=${_gp_sname:-$_gp_src} ;;
      esac
      ;;
  esac
  _gp_dst=${_gp_dst#refs/heads/}
  # A source git cannot resolve: git push itself refuses it. (HEAD: rsc_repo found the work tree;
  # an unborn HEAD makes the tier unknown, which is noted.)
  if [ -z "$_gp_rev" ]; then
    [ "$_gp_src" = HEAD ] || return 0
    _gp_rev=HEAD
  fi
  gate_push_commits "$_gp_src" "$_gp_rev" "$_gp_what"
  [ -z "$BLOCKS" ] || return 0
  if [ "$RSC_HAS_DEFAULT" = 1 ] && [ "$_gp_dst" = "$RSC_DEFAULT_NAME" ]; then
    gate_push_default "$_gp_what" "$_gp_rev"
  else
    gate_spec_panel "$_gp_what" "$_gp_rev" "$_gp_dst" "$_gp_sname"
  fi
}

# gate_push_commits SRC REV WHAT — once per pushed commit REV (SRC as written): authorship and
# secrets of what it adds to the default branch, and its tier (cached for gate_spec_panel and
# gate_push_default) from the same diff. Over MAX_PUSHED distinct commits, or past pre-bash's
# deadline (over_time): blocked.
gate_push_commits() {
  rsc_cached "$_GP_DONE" "$RSC_TOP $2" && return 0
  _GP_N=$((_GP_N + 1))
  if [ "$_GP_N" -gt "$MAX_PUSHED" ]; then
    block "too many git pushes in one command (over $MAX_PUSHED distinct commits to check); split it into several commands."
    return 0
  fi
  over_time && return 0
  _GP_DONE="$_GP_DONE$RSC_TOP $2$TAB$NL"
  gate_authorship_push "$1" "$3" "$2"
  [ -z "$BLOCKS" ] || return 0
  [ "$RSC_HAS_DEFAULT" = 1 ] || return 0 # gate_authorship_push noted it
  _pc_diff=$(rsc_diff "$RSC_TOP" -U0 --no-renames "$RSC_DEFAULT_REF...$2" 2> /dev/null) || return 0
  gate_secrets_diff "$1" "$3" "$_pc_diff"
  [ -z "$BLOCKS" ] && [ "$RSC_HAS_ROOT" = 1 ] || return 0
  _pc_out=$([ -z "$_pc_diff" ] || printf '%s\n' "$_pc_diff" | awk -v base="$RSC_DEFAULT_REF" -f "$LIB/risk-tier.awk") || return 0
  rsc_tier_store "$RSC_DEFAULT_REF" "$2" "$_pc_out"
}

# gate_push_delete REF — a push that deletes REF on the remote: the default branch is the human's.
gate_push_delete() {
  [ "$RSC_HAS_DEFAULT" = 1 ] || return 0
  [ "${1#refs/heads/}" = "$RSC_DEFAULT_NAME" ] || return 0
  block "git push deleting $1: deleting the default branch is left to the human."
}

# gate_push_default WHAT SRC — a push onto the default branch merges SRC into it: at tier 2 the
# human merges in the forge, as with gh pr merge and git merge.
gate_push_default() {
  [ "$RSC_HAS_ROOT" = 1 ] || return 0
  if ! rsc_tier "$RSC_DEFAULT_REF" "$2"; then
    note "$1: risk tier unknown ($RSC_TIER_ERR); the tier-2 merge gate did not run"
    return 0
  fi
  [ "$RSC_TIER" = 2 ] || return 0
  block "$1: pushes onto the default branch $RSC_DEFAULT_NAME, which merges it: tier-2 change ($RSC_TIER_WHY). The human merges this in the forge, after approving it; an agent never merges tier 2 (ship skill)."
}

# gate_push_all DIR — git push --all / --branches / --mirror / a glob refspec: every local branch
# that differs from origin's copy is judged as \`git push origin B:B\`. Over 20 such branches the
# push is blocked: the checks would not fit in the hook's time, so the branches go one by one.
gate_push_all() {
  _pa_refs=$(git -C "$RSC_TOP" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes/origin 2> /dev/null) || {
    note "git push --all: cannot list the branches; nothing checked"
    return 0
  }
  _pa_remote=' '
  while read -r _pa_ref _pa_oid; do
    case $_pa_ref in refs/remotes/origin/*) _pa_remote="$_pa_remote${_pa_ref#refs/remotes/origin/}=$_pa_oid " ;; esac
  done << EOF
$_pa_refs
EOF
  _pa_list=''
  _pa_n=0
  while read -r _pa_ref _pa_oid; do
    case $_pa_ref in refs/heads/*) ;; *) continue ;; esac
    _pa_b=${_pa_ref#refs/heads/}
    case $_pa_remote in *" $_pa_b=$_pa_oid "*) continue ;; esac
    _pa_n=$((_pa_n + 1))
    _pa_list="$_pa_list$_pa_b
"
  done << EOF
$_pa_refs
EOF
  if [ "$_pa_n" -gt 20 ]; then
    block "git push --all: $_pa_n local branches differ from origin; push them one at a time by name (git push origin <branch>) so each can be checked."
    return 0
  fi
  while IFS= read -r _pa_b; do
    [ -n "$_pa_b" ] || continue
    [ -z "$BLOCKS" ] || break
    gate_push "$1" "refs/heads/$_pa_b" "$_pa_b" "git push --all ($_pa_b)"
  done << EOF
$_pa_list
EOF
}

# gate_pr_create DIR HEAD — gh pr create [--head HEAD]: the spec + panel gate on that branch.
gate_pr_create() {
  if [ -z "$2" ]; then
    gate_spec_panel "gh pr create" HEAD "$RSC_BRANCH"
  elif git -C "$RSC_TOP" rev-parse -q --verify "refs/heads/$2" > /dev/null 2>&1; then
    gate_spec_panel "gh pr create --head $2" "refs/heads/$2" "$2"
  elif git -C "$RSC_TOP" rev-parse -q --verify "refs/remotes/origin/$2" > /dev/null 2>&1; then
    gate_spec_panel "gh pr create --head $2" "refs/remotes/origin/$2" "$2"
  else
    [ "$RSC_HAS_ROOT" = 1 ] && note "gh pr create --head $2: no such branch here; the tier-2 spec and panel gate did not run"
  fi
  return 0
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
      inq && tolower($0) ~ /^[ \t]*[-*+][ \t]+\[blocking\]/ { sub(/^[ \t]*[-*+][ \t]+/, ""); n++; if (n <= 5) out = out (n > 1 ? "; " : "") $0 }
      END { if (n) { print out (n > 5 ? "; ..." : ""); exit 3 } }
    ' "$_dq_pf") && continue
    _dq_found="$_dq_found; progress/$_dq_slug.md: $_dq_items"
  done << EOF
$_dq_specs
EOF
  [ -n "$_dq_found" ] || return 0
  block "gh pr merge: the decision queue still has blocking items${_dq_found}. They stop a merge until the human answers them."
}
