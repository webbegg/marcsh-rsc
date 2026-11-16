# hooks/lib/msg-check.awk — why a commit message attributes the work to an AI, or "".
#
#   msg_line(line)    one line of a message
#   msg_bad(text)     a whole message (split into lines, linear)
#   trailer_norm(t)   a `--trailer` argument in the `key: value` form (git also takes `key=value`)
#
# The rule is skills/ship/SKILL.md "The hard rule" (its grep at :27-31): no Co-Authored-By for an
# AI, no "Generated with" footer, no robot emoji. Checked per line, on the trailer and footer
# forms only, so a subject that merely mentions a tool ("fix the claude engine timeout") or a
# human co-author whose e-mail contains "ai" (gmail) is not blocked. The ship grep's bare
# `claude code` alternative is left out for that reason.
# Run with LC_ALL=C (the emoji is matched as bytes).

function msg_line(line,   l, rest) {
  sub(/\r$/, "", line)
  if (index(line, "\360\237\244\226")) return "robot-emoji footer: " msg_cut(line)
  l = tolower(line)
  sub(/^[ \t]+/, "", l)
  if (l ~ /^co-authored-by[ \t]*:/) {
    rest = substr(l, index(l, ":") + 1)
    if (rest ~ /claude|anthropic|openai|chatgpt|copilot|gemini|codex|devin|cursor|aider/ || rest ~ /(^|[^a-z0-9])ai([^a-z0-9]|$)/)
      return "AI co-author trailer: " msg_cut(line)
  }
  if (l ~ /^generated (with|by) /) return "\"generated with\" footer: " msg_cut(line)
  return ""
}

function msg_bad(text,   lines, n, i, r) {
  n = split(text, lines, "\n")
  for (i = 1; i <= n; i++) {
    r = msg_line(lines[i])
    if (r != "") return r
  }
  return ""
}

function trailer_norm(t,   k) {
  if (match(t, /^[ \t]*[A-Za-z0-9-]+[ \t]*[=:]/)) {
    k = substr(t, 1, RLENGTH - 1)
    sub(/[ \t]+$/, "", k)
    return k ":" substr(t, RLENGTH + 1)
  }
  return t
}

function msg_cut(s) {
  sub(/^[ \t]+/, "", s)
  return length(s) > 100 ? substr(s, 1, 100) "..." : s
}
