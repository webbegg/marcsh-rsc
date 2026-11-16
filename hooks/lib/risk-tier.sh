# hooks/lib/risk-tier.sh — rsc_risk_tier, the risk tier of a diff. Sourced (needs git.sh and LIB).
#
# rsc_risk_tier DIR BASE HEAD COMMITTED
#   The tier of BASE...HEAD in the repository at DIR, by skills/asdd/references/without-rsc-cli.md
#   §1 (path table, then content signals of the added lines; the highest wins). With COMMITTED=0
#   and HEAD being the checked-out commit, uncommitted and untracked work counts too (at most 200
#   untracked files are read, each up to 1 MB; all are classified by path).
#   Prints, one per line:
#     tier=<0|1|2|none>                          none = nothing to classify (never defaulted to 0)
#     base=<BASE>
#     reason=path <class>: <path>                each path at the highest tier
#     reason=content <class> (<signal>): <path>  each content hit (a secret's value is never shown)
#   Returns 1 with a message on stderr when BASE or HEAD is not a commit or they share no history.
#   Read-only, no network.

rsc_risk_tier() {
  _rk_dir=$1 _rk_base=$2 _rk_head=$3 _rk_committed=$4
  if ! git -C "$_rk_dir" merge-base "$_rk_base" "$_rk_head" > /dev/null 2>&1; then
    if ! git -C "$_rk_dir" rev-parse -q --verify "$_rk_base^{commit}" > /dev/null 2>&1; then
      echo "risk-tier: not a commit: $_rk_base" >&2
    elif ! git -C "$_rk_dir" rev-parse -q --verify "$_rk_head^{commit}" > /dev/null 2>&1; then
      echo "risk-tier: not a commit: $_rk_head" >&2
    else
      echo "risk-tier: $_rk_base and $_rk_head have no common ancestor" >&2
    fi
    return 1
  fi
  _rk_worktree=0
  if [ "$_rk_committed" = 0 ]; then
    case $_rk_head in
      HEAD) _rk_worktree=1 ;;
      *) [ "$(git -C "$_rk_dir" rev-parse HEAD 2> /dev/null)" = "$(git -C "$_rk_dir" rev-parse "$_rk_head^{commit}" 2> /dev/null)" ] && _rk_worktree=1 ;;
    esac
  fi
  {
    if [ "$_rk_worktree" = 1 ]; then
      printf '\001P\n'
      rsc_git "$_rk_dir" ls-files --others --exclude-standard
      printf '\001D\n'
    fi
    rsc_diff "$_rk_dir" -U0 --no-renames "$_rk_base...$_rk_head"
    if [ "$_rk_worktree" = 1 ]; then
      rsc_diff "$_rk_dir" -U0 --no-renames HEAD
      rsc_git "$_rk_dir" ls-files --others --exclude-standard | head -n 200 | while IFS= read -r _rk_f; do
        [ -f "$_rk_dir/$_rk_f" ] || continue
        _rk_size=$(wc -c < "$_rk_dir/$_rk_f" 2> /dev/null) || continue
        [ "$_rk_size" -le 1048576 ] || continue
        rsc_diff "$_rk_dir" -U0 --no-index -- /dev/null "$_rk_f"
      done
    fi
  } | awk -v base="$_rk_base" -f "$LIB/risk-tier.awk"
}
