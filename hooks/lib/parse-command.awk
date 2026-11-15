# hooks/lib/parse-command.awk — find the gated git/gh calls in a shell command line.
#
#   analyze(command, dir) — called by payload.awk; needs msg-check.awk.
#
# A small shell reader: quotes (single, double, backslash), comments, line continuations,
# `;` `&&` `||` `|` `&` `(` `)` and backticks between commands, here-documents (their body is
# kept for `git commit -F -`), env assignments and wrappers (env, command, exec, nohup, time,
# nice, sudo), `cd DIR` (followed for the commands after it), `git -C DIR`, and `sh -c` /
# `bash -c` / `eval` strings (read again as commands). It does not expand variables, aliases or
# globs: `git $SUB` or a git alias is not seen.
#
# Output, one line per gated call, fields separated by a tab (empty fields only at the end):
#   commit     <dir> <wide 0|1> <message file or "">   wide = -a/--all or paths given
#   commit-bad <dir> <reason>                          a visible message (-m, --trailer,
#                                                      -F - here-document) attributes to an AI
#   push       <dir>                                   not --dry-run, not --delete
#   pr-create  <dir>
#   pr-merge   <dir> <target or "">
#   merge      <dir> <target>                          one per target; not --abort etc.

function analyze(command, dir,   qi) {
  TAB = "\t"
  HOME_DIR = ENVIRON["HOME"]
  NQ = 1
  Q[1] = command
  QD[1] = dir
  for (qi = 1; qi <= NQ && qi <= 20; qi++) run(Q[qi], QD[qi])
}

function run(text, dir,   si, cur) {
  tokenize(text)
  cur = dir
  for (si = 1; si <= NSEG; si++) cur = segment(si, cur)
}

function enqueue(text, dir) {
  if (NQ >= 20) return
  NQ++
  Q[NQ] = text
  QD[NQ] = dir
}

function emit(line) {
  if (line in EMITTED) return
  EMITTED[line] = 1
  print line
}

# --- tokenizer: fills NSEG, NW[seg], W[seg, i] and HD[seg] (here-document bodies) ------------

function flush() {
  if (T_IN || T_WORD != "") {
    NW[NSEG]++
    W[NSEG, NW[NSEG]] = T_WORD
  }
  T_WORD = ""
  T_IN = 0
}

function newseg() {
  flush()
  if (NW[NSEG] == 0) return
  NSEG++
  NW[NSEG] = 0
  HD[NSEG] = ""
}

function tokenize(s,   n, i, c, nx, q, d, strip) {
  split("", W)
  split("", NW)
  split("", HD)
  NSEG = 1
  NW[1] = 0
  HD[1] = ""
  T_WORD = ""
  T_IN = 0
  NPEND = 0
  n = length(s)
  i = 1
  q = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (q == "'") {
      if (c == "'") q = ""
      else T_WORD = T_WORD c
      i++
      continue
    }
    if (q == "\"") {
      if (c == "\"") { q = ""; i++; continue }
      if (c == "\\") {
        nx = substr(s, i + 1, 1)
        if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { T_WORD = T_WORD nx; i += 2; continue }
        if (nx == "\n") { i += 2; continue }
      }
      T_WORD = T_WORD c
      i++
      continue
    }
    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      i += 2
      if (nx != "\n") { T_WORD = T_WORD nx; T_IN = 1 }
      continue
    }
    if (c == "'" || c == "\"") { q = c; T_IN = 1; i++; continue }
    if (c == " " || c == "\t" || c == "\r") { flush(); i++; continue }
    if (c == "#" && !T_IN && T_WORD == "") {
      while (i <= n && substr(s, i, 1) != "\n") i++
      continue
    }
    if (c == "\n") { newseg(); i = heredocs(s, i + 1); continue }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") { newseg(); i++; continue }
    if (c == "&") {
      if (T_WORD ~ /[<>]$/ || substr(s, i + 1, 1) == ">") { T_WORD = T_WORD c; T_IN = 1; i++; continue }
      newseg()
      i++
      continue
    }
    if (substr(s, i, 3) == "<<<") { T_WORD = T_WORD "<<<"; T_IN = 1; i += 3; continue }
    if (substr(s, i, 2) == "<<") {
      flush()
      i += 2
      strip = 0
      if (substr(s, i, 1) == "-") { strip = 1; i++ }
      while (substr(s, i, 1) == " " || substr(s, i, 1) == "\t") i++
      d = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (index(" \t\n;&|()<>", c)) break
        if (c != "'" && c != "\"" && c != "\\") d = d c
        i++
      }
      NPEND++
      PDELIM[NPEND] = d
      PSTRIP[NPEND] = strip
      PSEG[NPEND] = NSEG
      continue
    }
    T_WORD = T_WORD c
    T_IN = 1
    i++
  }
  flush()
}

# heredocs(s, i): i is the start of the line after a newline; reads the pending here-document
# bodies and returns the index after them.
function heredocs(s, i,   k, n, j, line, t, body) {
  n = length(s)
  for (k = 1; k <= NPEND; k++) {
    body = ""
    while (i <= n) {
      j = index(substr(s, i), "\n")
      if (j == 0) { line = substr(s, i); i = n + 1 }
      else { line = substr(s, i, j - 1); i += j }
      t = line
      if (PSTRIP[k]) sub(/^\t+/, "", t)
      if (t == PDELIM[k]) break
      body = body line "\n"
    }
    HD[PSEG[k]] = HD[PSEG[k]] body
  }
  NPEND = 0
  return i
}

# --- commands ---------------------------------------------------------------------------------

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

# A redirection word; bare ones (`>`, `2>`) take the next word as their target.
function is_redir(w) { return w ~ /^[0-9]*(>|<|&>)/ }
function bare_redir(w) { return w ~ /^[0-9]*(>|>>|<|<>|>\||&>|&>>)$/ }

function segment(si, cur,   nw, k, w, b, j, s) {
  nw = NW[si]
  k = 1
  while (k <= nw) {
    w = W[si, k]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
    if (w == "!" || w == "{" || w == "}" || w == "then" || w == "do" || w == "else" || w == "elif" || w == "if" || w == "while" || w == "until" || w == "exec" || w == "nohup" || w == "builtin") { k++; continue }
    if (w == "time") { k++; if (W[si, k] == "-p") k++; continue }
    if (w == "command") {
      k++
      if (W[si, k] == "-v" || W[si, k] == "-V") return cur
      if (W[si, k] == "-p") k++
      continue
    }
    if (w == "env") {
      k++
      while (k <= nw && (W[si, k] ~ /^-/ || W[si, k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        if (W[si, k] == "-u" || W[si, k] == "--unset") k++
        else if (W[si, k] == "-C" || W[si, k] == "--chdir") { cur = resolve(cur, W[si, k + 1]); k++ }
        else if (W[si, k] ~ /^--chdir=/) cur = resolve(cur, substr(W[si, k], 9))
        k++
      }
      continue
    }
    if (w == "sudo" || w == "doas" || w == "nice") {
      k++
      while (k <= nw && W[si, k] ~ /^-/) {
        if (W[si, k] ~ /^-[ugCnrtph]$/) k++
        k++
      }
      continue
    }
    break
  }
  if (k > nw) return cur
  w = W[si, k]
  b = base_name(w)
  if (b == "cd" || b == "pushd") {
    if (k + 1 <= nw && W[si, k + 1] == "--") k++
    if (k + 1 > nw) return HOME_DIR
    if (W[si, k + 1] == "-") return cur
    return resolve(cur, W[si, k + 1])
  }
  if (b == "sh" || b == "bash" || b == "dash" || b == "zsh" || b == "ksh" || b == "ash") {
    for (j = k + 1; j <= nw; j++) {
      if (W[si, j] ~ /^-[A-Za-z]*c[A-Za-z]*$/) { enqueue(W[si, j + 1], cur); break }
      if (W[si, j] !~ /^-/) break
    }
    return cur
  }
  if (b == "eval") {
    s = ""
    for (j = k + 1; j <= nw; j++) s = s (j > k + 1 ? " " : "") W[si, j]
    enqueue(s, cur)
    return cur
  }
  if (b == "git") git_cmd(si, k + 1, cur)
  else if (b == "gh") gh_cmd(si, k + 1, cur)
  return cur
}

function git_cmd(si, k, dir,   nw, w, sc) {
  nw = NW[si]
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
  if (sc == "commit") git_commit(si, k + 1, dir)
  else if (sc == "push") git_push(si, k + 1, dir)
  else if (sc == "merge") git_merge(si, k + 1, dir)
}

function check_msg(text) {
  if (CHK_REASON == "") CHK_REASON = msg_bad(text)
}

function git_commit(si, k, dir,   nw, w, wide, msgfile, j, ch, rest, arg) {
  nw = NW[si]
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
    if (w == "--trailer") { check_msg(W[si, k + 1]); k += 2; continue }
    if (w ~ /^--trailer=/) { check_msg(substr(w, 11)); k++; continue }
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
    check_msg(HD[si] != "" ? HD[si] : HD[si - 1])
    msgfile = ""
  }
  emit("commit" TAB dir TAB wide TAB msgfile)
  if (CHK_REASON != "") emit("commit-bad" TAB dir TAB CHK_REASON)
}

function git_push(si, k, dir,   nw, w) {
  nw = NW[si]
  for (; k <= nw; k++) {
    w = W[si, k]
    if (w == "-n" || w == "--dry-run" || w == "-d" || w == "--delete") return
  }
  emit("push" TAB dir)
}

function git_merge(si, k, dir,   nw, w, j) {
  nw = NW[si]
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

function gh_cmd(si, k, dir,   nw, w, act, target) {
  nw = NW[si]
  while (k <= nw && W[si, k] ~ /^-/) { if (W[si, k] == "-R" || W[si, k] == "--repo") k++; k++ }
  if (W[si, k] != "pr") return
  k++
  while (k <= nw && W[si, k] ~ /^-/) { if (W[si, k] == "-R" || W[si, k] == "--repo") k++; k++ }
  act = W[si, k]
  k++
  if (act == "create") { emit("pr-create" TAB dir); return }
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
