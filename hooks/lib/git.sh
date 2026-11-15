# hooks/lib/git.sh — git helpers shared by the hooks, risk-tier and sdd-root. Sourced, never run.
#
# Every call is read-only and independent of the user's git config: no colour, no external diff
# or textconv, fixed a/ b/ prefixes, unquoted paths, and GIT_OPTIONAL_LOCKS=0 so `git status` and
# `git diff` never refresh (write) the index. Few processes: a hook on pi must stay fast.

GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS

# rsc_git DIR ARGS... — git in DIR with a neutral config.
rsc_git() {
  _rg_dir=$1
  shift
  git -C "$_rg_dir" -c core.quotepath=off -c color.ui=never -c diff.noprefix=false -c log.showsignature=false "$@"
}

# rsc_diff DIR ARGS... — `git diff` with output that does not depend on the user's config.
rsc_diff() {
  _rd_dir=$1
  shift
  rsc_git "$_rd_dir" diff --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ "$@"
}

# rsc_default_branch DIR — sets RSC_DEFAULT_NAME (main) and RSC_DEFAULT_REF (origin/main).
# Order: refs/remotes/origin/HEAD, then main, then master (the remote-tracking ref when it
# exists, else the local branch). Returns 1 when none exists. One git call, no network.
rsc_default_branch() {
  RSC_DEFAULT_NAME=''
  RSC_DEFAULT_REF=''
  _db_refs=$(git -C "$1" for-each-ref --format='%(refname) %(symref)' refs/remotes/origin/HEAD \
    refs/remotes/origin/main refs/heads/main refs/remotes/origin/master refs/heads/master 2> /dev/null) || return 1
  _db_have=" "
  _db_sym=''
  while read -r _db_ref _db_target; do
    _db_have="$_db_have$_db_ref "
    [ "$_db_ref" = refs/remotes/origin/HEAD ] && _db_sym=$_db_target
  done << EOF
$_db_refs
EOF
  case $_db_sym in
    refs/remotes/origin/?*)
      case $_db_have in
        *" $_db_sym "*)
          RSC_DEFAULT_NAME=${_db_sym#refs/remotes/origin/}
          RSC_DEFAULT_REF=origin/$RSC_DEFAULT_NAME
          return 0
          ;;
      esac
      ;;
  esac
  for _db_n in main master; do
    case $_db_have in
      *" refs/remotes/origin/$_db_n "*) RSC_DEFAULT_NAME=$_db_n RSC_DEFAULT_REF=origin/$_db_n; return 0 ;;
      *" refs/heads/$_db_n "*) RSC_DEFAULT_NAME=$_db_n RSC_DEFAULT_REF=$_db_n; return 0 ;;
    esac
  done
  return 1
}

# rsc_repo DIR — sets RSC_TOP (the work tree root) and RSC_BRANCH (empty when HEAD is detached
# or unborn). Returns 1 when DIR is not in a work tree. One git call.
rsc_repo() {
  RSC_TOP=''
  RSC_BRANCH=''
  _rp_out=$(git -C "$1" rev-parse --show-toplevel --symbolic-full-name HEAD 2> /dev/null)
  _rp_rc=$?
  RSC_TOP=${_rp_out%%
*}
  if [ "$_rp_rc" != 0 ]; then
    # An unborn HEAD fails the second query; the first still names the root.
    [ -n "$RSC_TOP" ] && [ -d "$RSC_TOP" ] || { RSC_TOP=''; return 1; }
    return 0
  fi
  case $_rp_out in
    *"
refs/heads/"*) RSC_BRANCH=${_rp_out#*
refs/heads/} ;;
  esac
  [ -n "$RSC_TOP" ]
}

# rsc_context DIR — rsc_repo, rsc_default_branch and rsc_sdd_root for DIR (RSC_HAS_DEFAULT and
# RSC_HAS_ROOT say whether the last two found one). Cached for the last DIR. Returns 1 when DIR
# is not in a work tree.
rsc_context() {
  if [ -n "${_cx_dir:-}" ] && [ "$_cx_dir" = "$1" ]; then return "$_cx_rc"; fi
  _cx_dir=$1
  _cx_rc=1
  RSC_HAS_DEFAULT=0
  RSC_HAS_ROOT=0
  rsc_repo "$1" || return 1
  rsc_default_branch "$RSC_TOP" && RSC_HAS_DEFAULT=1
  rsc_sdd_root "$RSC_TOP" && RSC_HAS_ROOT=1
  _cx_rc=0
}

# rsc_sdd_root START — sets RSC_ROOT to the first directory, from START upward, that contains
# 02-DOCS. Returns 1 when there is none. Shell only: no process, no side effect.
rsc_sdd_root() {
  RSC_ROOT=''
  _sr_dir=$1
  while :; do
    if [ -d "$_sr_dir/02-DOCS" ]; then
      RSC_ROOT=${_sr_dir:-/}
      return 0
    fi
    case $_sr_dir in
      '' | / | */) return 1 ;;
    esac
    case $_sr_dir in
      /*/*) _sr_dir=${_sr_dir%/*} ;;
      /*) _sr_dir=/ ;;
      *) return 1 ;;
    esac
  done
}
