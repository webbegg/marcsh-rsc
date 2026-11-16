# hooks/lib/msg-check.awk — msg_bad(text): why a commit message attributes the work to an AI, or "".
#
# The rule is skills/ship/SKILL.md "The hard rule" (its grep at :27-31): no Co-Authored-By for an
# AI, no "Generated with" footer, no robot emoji. Checked per line, on the trailer and footer
# forms only, so a subject that merely mentions a tool ("fix the claude engine timeout") or a
# human co-author whose e-mail contains "ai" (gmail) is not blocked. The ship grep's bare
# `claude code` alternative is left out for that reason.
# Run with LC_ALL=C (the emoji is matched as bytes).

function msg_bad(text,   lines, n, i, line, l, rest) {
  n = split(text, lines, "\n")
  for (i = 1; i <= n; i++) {
    line = lines[i]
    sub(/\r$/, "", line)
    if (index(line, "\360\237\244\226")) return "robot-emoji footer: " msg_cut(line)
    l = tolower(line)
    sub(/^[ \t]+/, "", l)
    if (l ~ /^co-authored-by:/) {
      rest = substr(l, 16)
      if (rest ~ /claude|anthropic|openai|chatgpt|copilot|gemini|codex|devin/ || rest ~ /(^|[^a-z0-9])ai([^a-z0-9]|$)/)
        return "AI co-author trailer: " msg_cut(line)
    }
    if (l ~ /^generated (with|by) /) return "\"generated with\" footer: " msg_cut(line)
  }
  return ""
}

function msg_cut(s) {
  sub(/^[ \t]+/, "", s)
  return length(s) > 100 ? substr(s, 1, 100) "..." : s
}
