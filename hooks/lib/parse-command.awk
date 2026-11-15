# hooks/lib/parse-command.awk — find the gated git/gh calls in a shell command line.
#
#   gated_text(s)          1 when s may hold a gated call, read a file as commands or run a
#                          shell (cheap pre-filter, linear)
#   gated_lines(s)         the lines of s for which gated_text holds (commands over 256 KB)
#   analyze(command, dir)  prints the gated calls. Needs msg-check.awk and json-get.awk (tjoin).
#
# A small shell reader. Quotes (single, double, backslash), comments, line continuations,
# `;` `&&` `||` `|` `&` `(` `)` and backticks between commands, here-documents and here-strings,
# env assignments. Wrappers are unwrapped to the command they run: env (also -S, -C), command,
# exec, nohup, time, nice, ionice, sudo, doas, timeout, gtimeout, stdbuf, setsid, chronic, unbuffer,
# caffeinate, flock, script, watch, xargs, find -exec, parallel. `cd DIR`, `cd -`, `pushd` and
# `popd` are followed for the commands after them, and `git -C DIR`. Read again as commands:
# `sh -c` / `bash -c` / `eval` strings; what a shell reads on stdin (`sh <<EOF`, `bash <<<`,
# `sh < file`, `echo ... | sh`, `printf ... | bash`, `cat <<EOF | sh`, `cat file | sh`,
# `cat < file | sh`, `tee < file | sh`, `... | xargs sh -c`); a file passed to `source` / `.` or
# run as a shell's script (`sh file`, `bash -x ./file args`) or fed to its stdin, when it is inside
# the project ($CLAUDE_PROJECT_DIR, else the payload's cwd; elsewhere a note says it was not read).
#
# When a shell reads stdin from a command this reader cannot see through (`curl ... | sh`), every
# line of the command text that holds a `git` word followed by push/commit/merge, or a `gh` word
# followed by `pr`, is read as a command from that word on, with its quotes removed: the
# conservative reading, documented in the README.
#
# It does not expand variables, aliases or globs: `git $SUB` or a git alias is not seen. Nothing
# is executed; sourced files are only read.
#
# Linear in the command size: each line is scanned through a 1 KB window (see json-get.awk for
# why), runs of plain characters are taken with one match(), and words are joined with tjoin.
#
# Output, one line per gated call, fields separated by a tab (empty fields only at the end):
#   commit     <dir> <wide 0|1> <message file or "">   wide = -a/--all or paths given
#   commit-bad <dir> <reason>                          a visible message (-m, --trailer,
#                                                      -F - on stdin) attributes to an AI
#   push       <dir> <src> <dst or "@push" or "">      one per refspec; not --dry-run/--delete.
#                                                      dst "" = the name of src (HEAD: the
#                                                      current branch); @push = a plain push
#   push-del   <dir> <ref>                             a remote ref a push deletes (:ref,
#                                                      --delete / -d ref)
#   push-all   <dir>                                   --all, --branches, --mirror, a glob
#   pr-create  <dir> <head branch or "">
#   pr-merge   <dir> <target or "">
#   merge      <dir> <target>                          one per target; not --abort etc.
#   note       <dir> <text>                            something that could not be read
#   too-many   <dir> <n>                               over MAXG (20) distinct gated calls: the
#                                                      only line printed (the hook blocks)

function gated_call(s,   t, p) {
  t = " " s " "
  if (match(t, /[^A-Za-z0-9_-]git[^A-Za-z0-9_-]/)) {
    p = substr(t, RSTART + 1)
    if (index(p, "push") || index(p, "commit") || index(p, "merge")) return 1
  }
  if (match(t, /[^A-Za-z0-9_-]gh[^A-Za-z0-9_-]/)) {
    p = substr(t, RSTART + 1)
    if (match(p, /[^A-Za-z0-9_-]pr[^A-Za-z0-9_-]/)) return 1
  }
  return 0
}

# gated_call, a file read as commands (`source F`, `. F`), or a shell word anywhere (`sh < F`,
# `cat F | sh`, `bash F`): a shell may read a file or a pipe, so it always reaches the parser.
function gated_text(s,   t) {
  if (gated_call(s)) return 1
  t = " " s
  if (match(t, /[^A-Za-z0-9_.-](source|\.)[ \t]/)) return 1
  return match(t, /[^A-Za-z0-9_.-](sh|bash|dash|zsh|ksh|ash|mksh|yash|posh)([^A-Za-z0-9_.-]|$)/) > 0
}

function gated_lines(s,   n, L, i, m, K, l) {
  n = split(s, L, "\n")
  m = 0
  for (i = 1; i <= n; i++) {
    l = L[i]
    if (l ~ /git|gh|source|\.[ \t]|sh/ && gated_text(l)) K[++m] = l "\n"
  }
  return tjoin(K, m)
}

function analyze(command, dir,   qi) {
  TAB = "\t"
  HOME_DIR = ENVIRON["HOME"]
  WIN = 1024
  MAXQ = 20
  CAP = 262144
  SHELLS_RE = "^(sh|bash|dash|zsh|ksh|ash|mksh|yash|posh)$"
  PROJECT = ENVIRON["CLAUDE_PROJECT_DIR"]
  if (PROJECT !~ /^\//) PROJECT = dir
  PROJECT = normpath(PROJECT)
  MAXG = 20
  NQ = 0
  NPS = 0
  DEPTH = 0
  NEM = 0
  NGATED = 0
  NNOTE = 0
  enqueue_text(command, dir)
  for (qi = 1; qi <= NQ; qi++) run(qi)
  if (NGATED > MAXG) { print "too-many" TAB dir TAB NGATED; return }
  for (qi = 1; qi <= NEM; qi++) print EM[qi]
}

# --- the queue of texts to read: QL[q, line], QN[q] lines, QD[q] directory -----------------------

function enqueue_text(text, dir,   n, i, T, key) {
  if (NQ >= MAXQ) return
  key = dir SUBSEP text
  if (key in ENQ) return
  ENQ[key] = 1
  n = split(text, T, "\n")
  NQ++
  for (i = 1; i <= n; i++) QL[NQ, i] = T[i]
  QN[NQ] = n
  QD[NQ] = dir
}

function enqueue_range(q, a, b, dir,   i, key) {
  if (NQ >= MAXQ || b < a) return
  key = "range" SUBSEP q SUBSEP a SUBSEP b SUBSEP dir
  if (key in ENQ) return
  ENQ[key] = 1
  NQ++
  for (i = a; i <= b; i++) QL[NQ, i - a + 1] = QL[q, i]
  QN[NQ] = b - a + 1
  QD[NQ] = dir
}

function enqueue_hd(seg, dir,   m) {
  for (m = 1; m <= HDN[seg]; m++) enqueue_range(CURQ, HDA[seg, m], HDB[seg, m], dir)
}

function hd_text(seg,   m, i, n, P) {
  n = 0
  for (m = 1; m <= HDN[seg]; m++)
    for (i = HDA[seg, m]; i <= HDB[seg, m]; i++) P[++n] = QL[CURQ, i] "\n"
  return tjoin(P, n)
}

function run(q,   si, cur) {
  tokenize(q)
  cur = QD[q]
  CD_OLD = ""
  DSN = 0
  for (si = 1; si <= NSEG; si++) cur = cmd_at(si, 1, NW[si], cur)
}

# emit(line): queues an output line once. Over MAXG distinct gated calls only the count is kept
# (analyze prints a too-many line instead); notes are kept up to MAXG.
function emit(line,   kind) {
  if (line in EMITTED) return
  EMITTED[line] = 1
  kind = substr(line, 1, index(line, TAB) - 1)
  if (kind == "note") { if (++NNOTE <= MAXG) EM[++NEM] = line; return }
  if (kind != "commit-bad" && ++NGATED > MAXG) return
  EM[++NEM] = line
}

# --- tokenizer: NSEG segments; NW[seg] words W[seg, i]; SP[seg] = 1 when stdin is a pipe from
# segment seg - 1; HDN[seg] here-document bodies, lines HDA..HDB of text CURQ ---------------------

function tokenize(q,   n, li, k, a, t, found, s) {
  split("", W)
  split("", NW)
  split("", HDN)
  split("", HDA)
  split("", HDB)
  split("", SP)
  NSEG = 1
  NW[1] = 0
  HDN[1] = 0
  SP[1] = 0
  TPN = 0
  T_IN = 0
  T_LAST = ""
  QS = ""
  NPEND = 0
  CURQ = q
  n = QN[q]
  li = 1
  while (li <= n) {
    if (tok_line(QL[q, li++])) continue
    if (QS != "") { addp("\n"); continue }
    newseg()
    for (k = 1; k <= NPEND; k++) {
      a = li
      found = 0
      while (li <= n) {
        t = QL[q, li++]
        if (PSTRIP[k] && substr(t, 1, 1) == "\t") sub(/^\t+/, "", t)
        if (t == PDELIM[k]) { found = 1; break }
      }
      s = PSEG[k]
      if (li - 1 - found >= a) {
        HDN[s]++
        HDA[s, HDN[s]] = a
        HDB[s, HDN[s]] = li - 1 - found
      }
    }
    NPEND = 0
  }
  flush()
}

# The line cursor: CS (the line), CW a window of it starting at CB, CP the position in CW.
function c_init(s) {
  CS = s
  CSN = length(s)
  CB = 1
  CW = (CSN <= WIN) ? s : substr(s, 1, WIN)
  CWN = length(CW)
  CP = 1
}

function c_more() {
  if (CP + 4 > CWN && CB + CWN <= CSN) {
    CB += CP - 1
    CW = substr(CS, CB, WIN)
    CWN = length(CW)
    CP = 1
  }
  return CP <= CWN
}

function c_end(o) { return CB + CP - 1 + o > CSN }

function addp(p) {
  TP[++TPN] = p
  T_IN = 1
  T_LAST = substr(p, length(p), 1)
}

function flush() {
  if (T_IN || TPN > 0) {
    NW[NSEG]++
    W[NSEG, NW[NSEG]] = (TPN == 1) ? TP[1] : tjoin(TP, TPN)
  }
  TPN = 0
  T_IN = 0
  T_LAST = ""
}

function newseg() {
  flush()
  if (NW[NSEG] == 0) return
  NSEG++
  NW[NSEG] = 0
  HDN[NSEG] = 0
  SP[NSEG] = 0
}

# tok_line(s): reads one line; returns 1 when it ends in a line continuation.
function tok_line(s,   c, nx, d, dn, strip) {
  c_init(s)
  while (c_more()) {
    c = substr(CW, CP, 1)
    if (QS == "'") {
      if (c == "'") { QS = ""; CP++; continue }
      if (match(substr(CW, CP), /^[^']+/)) { addp(substr(CW, CP, RLENGTH)); CP += RLENGTH }
      continue
    }
    if (QS == "\"") {
      if (c == "\"") { QS = ""; CP++; continue }
      if (c == "\\") {
        if (c_end(1)) return 1
        nx = substr(CW, CP + 1, 1)
        if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { addp(nx); CP += 2; continue }
        addp(c)
        CP++
        continue
      }
      if (match(substr(CW, CP), /^[^"\\]+/)) { addp(substr(CW, CP, RLENGTH)); CP += RLENGTH }
      continue
    }
    if (c == "\\") {
      if (c_end(1)) return 1
      addp(substr(CW, CP + 1, 1))
      CP += 2
      continue
    }
    if (c == "'" || c == "\"") { QS = c; T_IN = 1; CP++; continue }
    if (c == " " || c == "\t" || c == "\r") { flush(); CP++; continue }
    if (c == "#" && !T_IN && TPN == 0) return 0
    if (c == ";" || c == "(" || c == ")" || c == "`") { newseg(); CP++; continue }
    if (c == "|") {
      nx = substr(CW, CP + 1, 1)
      newseg()
      if (nx == "|") { CP += 2; continue }
      SP[NSEG] = 1
      CP += (nx == "&") ? 2 : 1
      continue
    }
    if (c == "&") {
      nx = substr(CW, CP + 1, 1)
      if (T_LAST == "<" || T_LAST == ">" || nx == ">") { addp(c); CP++; continue }
      newseg()
      CP += (nx == "&") ? 2 : 1
      continue
    }
    if (c == "<" && substr(CW, CP + 1, 1) == "<") {
      if (substr(CW, CP + 2, 1) == "<") { addp("<<<"); CP += 3; continue }
      flush()
      CP += 2
      strip = 0
      if (c_more() && substr(CW, CP, 1) == "-") { strip = 1; CP++ }
      while (c_more() && (substr(CW, CP, 1) == " " || substr(CW, CP, 1) == "\t")) CP++
      d = ""
      dn = 0
      while (c_more()) {
        c = substr(CW, CP, 1)
        if (index(" \t;&|()<>", c)) break
        if (c != "'" && c != "\"" && c != "\\" && dn < 256) { d = d c; dn++ }
        CP++
      }
      NPEND++
      PDELIM[NPEND] = d
      PSTRIP[NPEND] = strip
      PSEG[NPEND] = NSEG
      continue
    }
    if (match(substr(CW, CP), /^[^ \t\r\\'";|&()`<#]+/)) { addp(substr(CW, CP, RLENGTH)); CP += RLENGTH; continue }
    addp(c)
    CP++
  }
  return 0
}

# --- helpers --------------------------------------------------------------------------------------

function base_name(w) {
  sub(/.*\//, "", w)
  return w
}

function resolve(cur, p) {
  if (p == "") return cur
  if (p ~ /^\//) return p
  if (p == "~") return HOME_DIR
  if (p ~ /^~\//) return HOME_DIR substr(p, 2)
  return cur "/" p
}

function normpath(p,   n, A, i, m, S, out) {
  n = split(p, A, "/")
  m = 0
  for (i = 1; i <= n; i++) {
    if (A[i] == "" || A[i] == ".") continue
    if (A[i] == "..") { if (m > 0) m--; continue }
    S[++m] = A[i]
  }
  out = ""
  for (i = 1; i <= m; i++) out = out "/" S[i]
  return out == "" ? "/" : out
}

# A redirection word; bare ones (`>`, `2>`, `<<<`) take the next word as their target.
function is_redir(w) { return w ~ /^[0-9]*(>|<|&>)/ }
function bare_redir(w) { return w ~ /^[0-9]*(>|>>|<|<>|>\||&>|&>>|<<<)$/ }

# skip_opts(si, k, nw, SA, LA): the index of the first operand from k on. SA: the short options
# that take an argument; LA: " long names " that take one (always allowed as --name=value).
function skip_opts(si, k, nw, sa, la,   w, j, n) {
  while (k <= nw) {
    w = W[si, k]
    if (w == "--") return k + 1
    if (w !~ /^-./) return k
    if (substr(w, 1, 2) == "--") {
      if (!index(w, "=") && la != "" && index(la, " " substr(w, 3) " ")) k++
      k++
      continue
    }
    n = length(w)
    for (j = 2; j <= n; j++) if (sa != "" && index(sa, substr(w, j, 1))) { if (j == n) k++; break }
    k++
  }
  return k
}

function shq(w,   n, P, i) {
  if (w ~ /^[A-Za-z0-9_.\/:@%+=,-]+$/) return w
  n = split(w, P, "'")
  for (i = 1; i < n; i++) P[i] = P[i] "'\\''"
  return "'" tjoin(P, n) "'"
}

function wjoin(si, a, b, sep,   i, n, P) {
  n = 0
  for (i = a; i <= b; i++) P[++n] = (i < b) ? W[si, i] sep : W[si, i]
  return tjoin(P, n)
}

function qjoin(si, a, b,   i, n, P) {
  n = 0
  for (i = a; i <= b; i++) P[++n] = (i < b) ? shq(W[si, i]) " " : shq(W[si, i])
  return tjoin(P, n)
}

# unesc(s): the `\n` escapes of echo/printf as newlines.
function unesc(s,   n, P, i) {
  n = split(s, P, "\\\\n")
  for (i = 1; i < n; i++) P[i] = P[i] "\n"
  return tjoin(P, n)
}

function unquote(s,   n, P) {
  n = split(s, P, "[\"']")
  return tjoin(P, n)
}

function repl_str(w, r, v,   i, out) {
  if (r == "") return w
  out = ""
  while ((i = index(w, r)) > 0) {
    out = out substr(w, 1, i - 1) v
    w = substr(w, i + length(r))
  }
  return out w
}

# Pseudo segments: a command built from other words (xargs with its input, find -exec).
function pseudo() {
  NPS++
  PSID = "x" NPS
  NW[PSID] = 0
  HDN[PSID] = 0
  SP[PSID] = 0
  return PSID
}

function padd(ps, w) {
  NW[ps]++
  W[ps, NW[ps]] = w
}

function sub_cmd(ps, cur) {
  if (DEPTH >= 8) return
  DEPTH++
  cmd_at(ps, 1, NW[ps], cur)
  DEPTH--
}

# --- commands ---------------------------------------------------------------------------------

# cmd_at(si, k, nw, cur): the command in words k..nw of segment si, run in cur; returns the
# directory the commands after it run in.
function cmd_at(si, k, nw, cur,   ret, w, b, j) {
  ret = cur
  while (k <= nw) {
    w = W[si, k]
    b = base_name(w)
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    if (w == "!" || w == "{" || w == "}" || w == "then" || w == "do" || w == "else" || w == "elif" || w == "if" || w == "while" || w == "until" || w == "builtin") { k++; continue }
    if (b == "nohup" || b == "chronic" || b == "unbuffer" || b == "setsid") { k = skip_opts(si, k + 1, nw, "", ""); continue }
    if (b == "exec") { k = skip_opts(si, k + 1, nw, "a", ""); continue }
    if (b == "time") { k = skip_opts(si, k + 1, nw, "of", " output format "); continue }
    if (b == "nice") { k = skip_opts(si, k + 1, nw, "n", " adjustment "); continue }
    if (b == "caffeinate") { k = skip_opts(si, k + 1, nw, "tw", ""); continue }
    if (b == "stdbuf") { k = skip_opts(si, k + 1, nw, "ioe", " input output error "); continue }
    if (b == "sudo") { k = skip_opts(si, k + 1, nw, "ugChprtUDRT", " user group close-from host prompt role type other-user chdir chroot command-timeout "); continue }
    if (b == "doas") { k = skip_opts(si, k + 1, nw, "aCu", ""); continue }
    if (b == "timeout" || b == "gtimeout") { k = skip_opts(si, k + 1, nw, "ks", " kill-after signal ") + 1; continue }
    if (b == "ionice") {
      for (j = k + 1; j <= nw && W[si, j] ~ /^-/; j++)
        if (W[si, j] ~ /^-[A-Za-z0-9]*[pPu]/ || W[si, j] ~ /^--(pid|pgid|uid)/) return ret
      k = skip_opts(si, k + 1, nw, "cn", " class classdata ")
      continue
    }
    if (b == "command") {
      if (W[si, k + 1] ~ /^-[A-Za-z]*[vV]/) return ret
      k = skip_opts(si, k + 1, nw, "", "")
      continue
    }
    if (b == "env") {
      k = env_opts(si, k + 1, nw, cur)
      if (k < 0) return ret
      cur = ENV_CUR
      continue
    }
    if (b == "flock") { k = flock_k(si, k + 1, nw, cur); if (k < 0) return ret; continue }
    if (b == "script") { k = script_k(si, k + 1, nw, cur); if (k < 0) return ret; continue }
    break
  }
  if (k > nw) return ret
  w = W[si, k]
  b = base_name(w)
  if (b == "cd" || b == "pushd" || b == "popd") return chdir(si, k + 1, nw, cur, b)
  if (b == "source" || w == ".") { if (k < nw) source_file(W[si, k + 1], cur, "source"); return ret }
  if (b ~ SHELLS_RE) { shell_cmd(si, k + 1, nw, cur); return ret }
  if (b == "eval") { enqueue_text(wjoin(si, k + 1, nw, " "), cur); return ret }
  if (b == "xargs") { xargs_cmd(si, k + 1, nw, cur); return ret }
  if (b == "find") { find_cmd(si, k + 1, nw, cur); return ret }
  if (b == "parallel") { parallel_cmd(si, k + 1, nw, cur); return ret }
  if (b == "watch") {
    k = skip_opts(si, k + 1, nw, "nq", " interval equexit ")
    if (k <= nw) enqueue_text(wjoin(si, k, nw, " "), cur)
    return ret
  }
  if (b == "git") git_cmd(si, k + 1, nw, cur)
  else if (b == "gh") gh_cmd(si, k + 1, nw, cur)
  return ret
}

# env_opts: the index of env's command (ENV_CUR: its directory), or -1 when -S queued it.
function env_opts(si, k, nw, cur,   w, j, n, ch, s, split_s) {
  ENV_CUR = cur
  while (k <= nw) {
    w = W[si, k]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w == "-") { k++; continue }
    if (w == "--") return k + 1
    if (w !~ /^-/) return k
    split_s = 0
    if (w ~ /^--split-string=/) { s = substr(w, 16); split_s = 1; k++ }
    else if (w == "--split-string") { s = W[si, k + 1]; split_s = 1; k += 2 }
    else if (w ~ /^--chdir=/) { ENV_CUR = resolve(ENV_CUR, substr(w, 9)); k++; continue }
    else if (w == "--chdir") { ENV_CUR = resolve(ENV_CUR, W[si, k + 1]); k += 2; continue }
    else if (w == "--unset") { k += 2; continue }
    else if (w ~ /^--/) { k++; continue }
    else {
      n = length(w)
      for (j = 2; j <= n; j++) {
        ch = substr(w, j, 1)
        if (index("SuCP", ch)) {
          s = substr(w, j + 1)
          if (s == "") { s = W[si, k + 1]; k++ }
          if (ch == "C") ENV_CUR = resolve(ENV_CUR, s)
          if (ch == "S") split_s = 1
          break
        }
      }
      k++
    }
    if (!split_s) continue
    enqueue_text(s " " qjoin(si, k, nw), ENV_CUR)
    return -1
  }
  return k
}

# flock [opts] FILE (-c CMD | CMD ARGS...): the index of CMD, or -1 when -c queued it.
function flock_k(si, k, nw, cur,   w) {
  while (k <= nw) {
    w = W[si, k]
    if (w == "-c" || w == "--command") { enqueue_text(W[si, k + 1], cur); return -1 }
    if (w ~ /^--command=/) { enqueue_text(substr(w, 11), cur); return -1 }
    if (w == "--") { k++; break }
    if (w !~ /^-./) break
    if (w == "-w" || w == "-E" || w ~ /^--(timeout|wait|conflict-exit-code)$/) k++
    k++
  }
  k++
  w = W[si, k]
  if (w == "-c" || w == "--command") { enqueue_text(W[si, k + 1], cur); return -1 }
  if (w ~ /^--command=/) { enqueue_text(substr(w, 11), cur); return -1 }
  return k
}

# script [opts] [-c CMD] [FILE [CMD ARGS...]] (util-linux and BSD forms).
function script_k(si, k, nw, cur,   w, n, j) {
  while (k <= nw) {
    w = W[si, k]
    if (w == "-c" || w == "--command") { enqueue_text(W[si, k + 1], cur); return -1 }
    if (w ~ /^--command=/) { enqueue_text(substr(w, 11), cur); return -1 }
    if (w == "--") { k++; break }
    if (w !~ /^-./) break
    if (w ~ /^--/) {
      if (w ~ /^--(log-io|log-in|log-out|log-timing|logging-format|output-limit|echo)$/) k++
      k++
      continue
    }
    n = length(w)
    for (j = 2; j <= n; j++) {
      if (substr(w, j, 1) == "c") { enqueue_text(j < n ? substr(w, j + 1) : W[si, k + 1], cur); return -1 }
      if (index("BIOTmEotF", substr(w, j, 1))) { if (j == n) k++; break }
    }
    k++
  }
  k++
  w = W[si, k]
  if (w == "-c" || w == "--command") { enqueue_text(W[si, k + 1], cur); return -1 }
  if (w ~ /^--command=/) { enqueue_text(substr(w, 11), cur); return -1 }
  return k
}

function chdir(si, k, nw, cur, b,   t, d) {
  while (k <= nw && W[si, k] ~ /^-[LPe@]+$/) k++
  if (k <= nw && W[si, k] == "--") k++
  t = (k <= nw) ? W[si, k] : ""
  if (b == "popd") {
    if (DSN == 0) return cur
    d = DST[DSN--]
    CD_OLD = cur
    return d
  }
  if (b == "pushd") {
    if (t ~ /^[+-][0-9]+$/) return cur
    if (t == "") {
      if (DSN == 0) return cur
      d = DST[DSN]
      DST[DSN] = cur
      CD_OLD = cur
      return d
    }
    DST[++DSN] = cur
    CD_OLD = cur
    return resolve(cur, t)
  }
  if (t == "-") {
    if (CD_OLD == "") return cur
    d = CD_OLD
    CD_OLD = cur
    return d
  }
  CD_OLD = cur
  return t == "" ? HOME_DIR : resolve(cur, t)
}

# source_file(p, cur, what): queues the file's lines when it is inside the project; else a note
# (what: how the file is read, for the note).
function source_file(p, cur, what,   path, n, r, line, bytes, i, m, FL, key) {
  if (p == "") return
  if (p ~ /[$`*?]/) { emit("note" TAB cur TAB what " " p ": the path is not literal, the file was not read"); return }
  path = normpath(resolve(cur, p))
  if (PROJECT != "/" && substr(path, 1, length(PROJECT) + 1) != PROJECT "/") {
    emit("note" TAB cur TAB what " " p ": outside the project (" PROJECT "), the file was not read")
    return
  }
  key = "file" SUBSEP path SUBSEP cur
  if (NQ >= MAXQ || (key in ENQ)) return
  ENQ[key] = 1
  n = 0
  bytes = 0
  while ((r = (getline line < path)) > 0) {
    FL[++n] = line
    bytes += length(line) + 1
    if (n >= 200000) break
  }
  close(path)
  if (n == 0) {
    if (r < 0) emit("note" TAB cur TAB what " " p ": cannot read the file, it was not read")
    return
  }
  NQ++
  m = 0
  for (i = 1; i <= n; i++) if (bytes <= CAP || gated_text(FL[i])) QL[NQ, ++m] = FL[i]
  QN[NQ] = m
  QD[NQ] = cur
}

# stdin_src(si): what the command of segment si reads on stdin. SRC = hd (here-documents of
# segment SRC_SEG), text (SRC_TEXT), file (paths SRC_F[1..SRC_NF]; SRC_TEXT = the first),
# unknown (a pipe from a command this reader cannot see through) or none. Through a pipe, the
# producer is read: echo and printf give text; cat gives its files, else (like tee) its own stdin.
function stdin_src(si,   j, w, n) {
  SRC = "none"
  SRC_TEXT = ""
  SRC_SEG = ""
  SRC_NF = 0
  if (HDN[si] > 0) { SRC = "hd"; SRC_SEG = si; return }
  n = NW[si]
  for (j = 1; j <= n; j++) {
    w = W[si, j]
    if (substr(w, 1, 3) == "<<<") { SRC = "text"; SRC_TEXT = (w == "<<<") ? W[si, j + 1] : substr(w, 4); return }
    if (w == "<" || w == "0<") { src_file(W[si, j + 1]); return }
    if (w ~ /^0?<[^<>&(]/) { src_file(substr(w, index(w, "<") + 1)); return }
  }
  if (!SP[si]) return
  SRC = "unknown"
  if (si - 1 < 1 || PDEPTH >= 16) return
  PDEPTH++
  producer(si - 1)
  PDEPTH--
}

function src_file(p) {
  SRC = "file"
  SRC_NF = 1
  SRC_F[1] = p
  SRC_TEXT = p
}

# producer(p): stdin_src's reading of segment p, whose output is piped on.
function producer(p,   k, b, j, w, nf, ops) {
  k = 1
  while (k <= NW[p]) {
    w = W[p, k]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    break
  }
  b = base_name(W[p, k])
  if (b == "cat" || b == "tee") {
    nf = 0
    ops = 0
    if (b == "cat") {
      for (j = k + 1; j <= NW[p]; j++) {
        w = W[p, j]
        if (is_redir(w)) { if (bare_redir(w)) j++; continue }
        if (!ops && w == "--") { ops = 1; continue }
        if (w == "-" || (!ops && w ~ /^-./)) continue
        SRC_F[++nf] = w
      }
    }
    if (nf > 0) { SRC = "file"; SRC_NF = nf; SRC_TEXT = SRC_F[1]; return }
    stdin_src(p)
    return
  }
  if (b == "echo") {
    k++
    while (k <= NW[p] && W[p, k] ~ /^-[neE]+$/) k++
    SRC = "text"
    SRC_TEXT = unesc(wjoin(p, k, NW[p], " "))
    return
  }
  if (b == "printf") {
    k++
    if (W[p, k] == "--") k++
    if (W[p, k] == "-v") { SRC = "none"; return }
    SRC = "text"
    SRC_TEXT = unesc(W[p, k]) "\n" wjoin(p, k + 1, NW[p], "\n")
    return
  }
}

# A shell reading its commands on stdin.
function stdin_shell(si, cur,   i, n, F) {
  stdin_src(si)
  if (SRC == "hd") enqueue_hd(SRC_SEG, cur)
  else if (SRC == "text") enqueue_text(SRC_TEXT, cur)
  else if (SRC == "file") {
    n = SRC_NF
    for (i = 1; i <= n; i++) F[i] = SRC_F[i]
    for (i = 1; i <= n; i++) source_file(F[i], cur, "a shell reads")
  }
  else if (SRC == "unknown") fallback(cur)
}

# fallback(cur): stdin comes from a command this reader cannot see through. Every line of the
# command text (and of the text being read) that holds a gated pattern is read as a command from
# its git/gh word on, without quotes.
function fallback(cur) {
  fallback_text(1, cur)
  if (CURQ != 1) fallback_text(CURQ, cur)
}

function fallback_text(q, cur,   i, t) {
  if (q in FB) return
  FB[q] = 1
  for (i = 1; i <= QN[q]; i++) {
    t = " " QL[q, i]
    if (!gated_call(t)) continue
    if (match(t, /[^A-Za-z0-9_-](git|gh)[^A-Za-z0-9_-]/)) enqueue_text(unquote(substr(t, RSTART + 1)), cur)
  }
}

function shell_cmd(si, k, nw, cur,   w, stdin) {
  stdin = 0
  while (k <= nw) {
    w = W[si, k]
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    if (w == "-") { stdin = 1; break }
    if (w == "--") { k++; break }
    if (w ~ /^[-+][oO]$/ || w == "--rcfile" || w == "--init-file") { k += 2; continue }
    if (w ~ /^--/) { k++; continue }
    if (w ~ /^[-+][A-Za-z]+$/) {
      if (w ~ /^-[A-Za-z]*c/) {
        if (k < nw) enqueue_text(W[si, k + 1], cur)
        else stdin_shell(si, cur)
        return
      }
      if (w ~ /^-[A-Za-z]*s/) stdin = 1
      k++
      continue
    }
    break
  }
  while (k <= nw && is_redir(W[si, k])) { if (bare_redir(W[si, k])) k++; k++ }
  if (stdin || k > nw) stdin_shell(si, cur)
  else source_file(W[si, k], cur, "a shell runs")
}

function xargs_cmd(si, k, nw, cur,   w, repl, j, n, ch, rest, t, L, i, m, ps) {
  repl = ""
  while (k <= nw) {
    w = W[si, k]
    if (w == "--") { k++; break }
    if (w !~ /^-./) break
    if (substr(w, 1, 2) == "--") {
      if (w == "--replace") repl = "{}"
      else if (w ~ /^--replace=/) repl = substr(w, 11)
      else if (w ~ /^--(arg-file|delimiter|max-args|max-procs|max-chars|process-slot-var)$/) k++
      k++
      continue
    }
    n = length(w)
    for (j = 2; j <= n; j++) {
      ch = substr(w, j, 1)
      rest = substr(w, j + 1)
      if (index("adEILnPsJRS", ch)) {
        if (rest == "") { rest = W[si, k + 1]; k++ }
        if (ch == "I" || ch == "J") repl = rest
        break
      }
      if (ch == "i") { repl = (rest == "") ? "{}" : rest; break }
      if (ch == "e" || ch == "l") break
    }
    k++
  }
  if (k > nw) return
  # `... | xargs sh -c`: the command string comes from stdin.
  if (base_name(W[si, k]) ~ SHELLS_RE && W[si, nw] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
    stdin_src(si)
    if (SRC == "hd") enqueue_text(unquote(hd_text(SRC_SEG)), cur)
    else if (SRC == "text") enqueue_text(unquote(SRC_TEXT), cur)
    else if (SRC != "none") fallback(cur)
    return
  }
  stdin_src(si)
  if (SRC == "text" || SRC == "hd") {
    t = (SRC == "hd") ? hd_text(SRC_SEG) : SRC_TEXT
    if (repl != "") {
      n = split(t, L, "\n")
      m = 0
      for (i = 1; i <= n && m < 10; i++) {
        if (L[i] == "") continue
        m++
        ps = pseudo()
        for (j = k; j <= nw; j++) padd(ps, repl_str(W[si, j], repl, L[i]))
        sub_cmd(ps, cur)
      }
      if (m > 0) return
    } else {
      ps = pseudo()
      for (j = k; j <= nw; j++) padd(ps, W[si, j])
      n = split(t, L, "[ \t\n]+")
      m = 0
      for (i = 1; i <= n && m < 200; i++) if (L[i] != "") { padd(ps, L[i]); m++ }
      sub_cmd(ps, cur)
      return
    }
  }
  # Input unknown: the command as written, without the words that take it.
  ps = pseudo()
  for (j = k; j <= nw; j++) if (repl == "" || !index(W[si, j], repl)) padd(ps, W[si, j])
  sub_cmd(ps, cur)
}

function find_cmd(si, k, nw, cur,   j, e, ps, i) {
  for (j = k; j <= nw; j++) {
    if (W[si, j] !~ /^-(exec|execdir|ok|okdir)$/) continue
    e = j + 1
    while (e <= nw && W[si, e] != ";" && W[si, e] != "+") e++
    ps = pseudo()
    for (i = j + 1; i < e; i++) if (!index(W[si, i], "{}")) padd(ps, W[si, i])
    sub_cmd(ps, cur)
    j = e
  }
}

function parallel_cmd(si, k, nw, cur,   j, tl, n, A, i, m, t, L) {
  k = skip_opts(si, k, nw, "jSaIdEnNLC", " jobs sshlogin arg-file colsep delimiter results joblog tmpdir max-args max-lines replace eof ")
  for (j = k; j <= nw && W[si, j] !~ /^::::?\+?$/; j++) continue
  if (j == k) return
  tl = wjoin(si, k, j - 1, " ")
  n = 0
  if (j <= nw) {
    for (i = j + 1; i <= nw && n < 10; i++) if (W[si, i] !~ /^::::?\+?$/) A[++n] = W[si, i]
  } else {
    stdin_src(si)
    if (SRC == "text" || SRC == "hd") {
      t = (SRC == "hd") ? hd_text(SRC_SEG) : SRC_TEXT
      m = split(t, L, "\n")
      for (i = 1; i <= m && n < 10; i++) if (L[i] != "") A[++n] = L[i]
    }
  }
  if (n == 0) { enqueue_text(tl, cur); return }
  for (i = 1; i <= n; i++) enqueue_text(index(tl, "{}") ? repl_str(tl, "{}", A[i]) : tl " " A[i], cur)
}

function git_cmd(si, k, nw, dir,   w, sc) {
  while (k <= nw) {
    w = W[si, k]
    if (w == "-C") { dir = resolve(dir, W[si, k + 1]); k += 2; continue }
    if (w == "--work-tree") { dir = resolve(dir, W[si, k + 1]); k += 2; continue }
    if (w ~ /^--work-tree=/) { dir = resolve(dir, substr(w, 13)); k++; continue }
    if (w == "-c" || w == "--git-dir" || w == "--namespace" || w == "--config-env" || w == "--super-prefix") { k += 2; continue }
    if (w ~ /^-/) { k++; continue }
    break
  }
  if (k > nw) return
  sc = W[si, k]
  if (sc == "commit") git_commit(si, k + 1, nw, dir)
  else if (sc == "push") git_push(si, k + 1, nw, dir)
  else if (sc == "merge") git_merge(si, k + 1, nw, dir)
}

function check_msg(text) {
  if (CHK_REASON == "") CHK_REASON = msg_bad(text)
}

function check_line(line) {
  if (CHK_REASON == "") CHK_REASON = msg_line(line)
}

function git_commit(si, k, nw, dir,   w, wide, msgfile, j, ch, rest, arg, m, i) {
  wide = 0
  msgfile = ""
  CHK_REASON = ""
  while (k <= nw) {
    w = W[si, k]
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    if (w == "--") { if (k < nw) wide = 1; break }
    if (w == "-m" || w == "--message") { check_msg(W[si, k + 1]); k += 2; continue }
    if (w ~ /^--message=/) { check_msg(substr(w, 11)); k++; continue }
    if (w == "-F" || w == "--file") { msgfile = W[si, k + 1]; k += 2; continue }
    if (w ~ /^--file=/) { msgfile = substr(w, 8); k++; continue }
    if (w == "--trailer") { check_msg(trailer_norm(W[si, k + 1])); k += 2; continue }
    if (w ~ /^--trailer=/) { check_msg(trailer_norm(substr(w, 11))); k++; continue }
    if (w == "--all" || w == "--include" || w == "--only" || w == "--interactive" || w == "--patch") { wide = 1; k++; continue }
    if (w ~ /^--(author|date|template|fixup|squash|cleanup|reuse-message|reedit-message|pathspec-from-file)$/) { k += 2; continue }
    if (w ~ /^--/) { k++; continue }
    if (w ~ /^-[A-Za-z]/) {
      for (j = 2; j <= length(w); j++) {
        ch = substr(w, j, 1)
        if (ch == "a" || ch == "i" || ch == "o" || ch == "p") wide = 1
        if (ch == "S") break
        if (index("mFCct", ch)) {
          rest = substr(w, j + 1)
          if (rest == "") { arg = W[si, k + 1]; k++ }
          else arg = rest
          if (ch == "m") check_msg(arg)
          else if (ch == "F") msgfile = arg
          break
        }
      }
      k++
      continue
    }
    wide = 1
    k++
  }
  if (msgfile == "-") {
    msgfile = ""
    stdin_src(si)
    if (SRC == "hd") {
      for (m = 1; m <= HDN[SRC_SEG]; m++)
        for (i = HDA[SRC_SEG, m]; i <= HDB[SRC_SEG, m]; i++) check_line(QL[CURQ, i])
    } else if (SRC == "text") check_msg(SRC_TEXT)
    else if (SRC == "file") msgfile = SRC_TEXT
  }
  emit("commit" TAB dir TAB wide TAB msgfile)
  if (CHK_REASON != "") emit("commit-bad" TAB dir TAB CHK_REASON)
}

function git_push(si, k, nw, dir,   w, j, all, repo, nref, ops, spec, c, src, dst, del) {
  del = 0
  for (j = k; j <= nw; j++) {
    w = W[si, j]
    if (w == "--dry-run") return
    if (w == "--delete") del = 1
    if (w ~ /^-[A-Za-z0-9]+$/) {
      if (index(w, "n")) return
      if (index(w, "d")) del = 1
    }
  }
  all = 0
  repo = 0
  nref = 0
  ops = 0
  for (j = k; j <= nw; j++) {
    w = W[si, j]
    if (is_redir(w)) { if (bare_redir(w)) j++; continue }
    if (!ops) {
      if (w == "--") { ops = 1; continue }
      if (w == "--all" || w == "--branches" || w == "--mirror") { all = 1; continue }
      if (w == "--repo" || w == "--push-option" || w == "--receive-pack" || w == "--exec" || w == "-o") { j++; continue }
      if (w ~ /^-/) continue
    }
    if (!repo) { repo = 1; continue }
    if (w == "tag" && j < nw) {
      j++
      if (del) emit("push-del" TAB dir TAB "refs/tags/" W[si, j])
      else emit("push" TAB dir TAB "refs/tags/" W[si, j] TAB "refs/tags/" W[si, j])
      nref++
      continue
    }
    spec = w
    sub(/^\+/, "", spec)
    if (del) {
      sub(/^[^:]*:/, "", spec)
      if (spec != "") emit("push-del" TAB dir TAB spec)
      continue
    }
    if (index(spec, "*")) { all = 1; continue }
    c = index(spec, ":")
    if (c) { src = substr(spec, 1, c - 1); dst = substr(spec, c + 1) }
    else { src = spec; dst = "" }
    nref++
    if (src != "") emit("push" TAB dir TAB src TAB dst)
    else if (dst != "") emit("push-del" TAB dir TAB dst)
  }
  if (del) return
  if (all) emit("push-all" TAB dir)
  else if (nref == 0) emit("push" TAB dir TAB "HEAD" TAB "@push")
}

function git_merge(si, k, nw, dir,   w, j) {
  for (j = k; j <= nw; j++) {
    w = W[si, j]
    if (w == "--abort" || w == "--continue" || w == "--quit" || w == "--skip") return
  }
  while (k <= nw) {
    w = W[si, k]
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    if (w == "-m" || w == "-F" || w == "--file" || w == "-s" || w == "--strategy" || w == "-X" || w == "--strategy-option" || w == "--into-name" || w == "--cleanup") { k += 2; continue }
    if (w == "--") { k++; continue }
    if (w ~ /^-/) { k++; continue }
    emit("merge" TAB dir TAB w)
    k++
  }
}

function gh_cmd(si, k, nw, dir,   w, act, target, head) {
  while (k <= nw && W[si, k] ~ /^-/) { if (W[si, k] == "-R" || W[si, k] == "--repo") k++; k++ }
  if (W[si, k] != "pr") return
  k++
  while (k <= nw && W[si, k] ~ /^-/) { if (W[si, k] == "-R" || W[si, k] == "--repo") k++; k++ }
  act = W[si, k]
  k++
  if (act == "create" || act == "new") {
    head = ""
    for (; k <= nw; k++) {
      w = W[si, k]
      if (w == "-H" || w == "--head") { head = W[si, k + 1]; k++ }
      else if (w ~ /^--head=/) head = substr(w, 8)
      else if (w ~ /^-H./) head = substr(w, 3)
    }
    sub(/^[^:]*:/, "", head)
    emit("pr-create" TAB dir TAB head)
    return
  }
  if (act != "merge") return
  target = ""
  while (k <= nw) {
    w = W[si, k]
    if (is_redir(w)) { if (bare_redir(w)) k++; k++; continue }
    if (w == "-b" || w == "--body" || w == "-F" || w == "--body-file" || w == "-t" || w == "--subject" || w == "-A" || w == "--author-email" || w == "--match-head-commit" || w == "-R" || w == "--repo") { k += 2; continue }
    if (w ~ /^-/) { k++; continue }
    if (target == "") target = w
    k++
  }
  emit("pr-merge" TAB dir TAB target)
}
