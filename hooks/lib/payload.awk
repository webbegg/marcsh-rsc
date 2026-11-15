# hooks/lib/payload.awk — main program of the hook's one awk pass:
#
#   awk -f json-get.awk -f msg-check.awk -f parse-command.awk -f payload.awk < payload.json
#
# Reads the PreToolUse payload, takes tool_input.command and cwd (falling back to
# $CLAUDE_PROJECT_DIR, then $PWD) and prints the gated calls (parse-command.awk's format).
# Exit 0 (nothing printed: nothing to check), or 3 when the payload is not valid JSON.
#
# Cost: the payload is read once (linear). A command that cannot hold a gated call (gated_text:
# no `git` word followed by push/commit/merge, no `gh` word followed by `pr`, no `source`/`.`, no
# shell word such as `sh` or `bash`) is not parsed at all. A command over 256 KB is cut down to its lines that could hold one
# (gated_lines) before it is parsed.

{ T[++NT] = $0 "\n" }

END {
  JSON_WANT["tool_input.command"] = 1
  JSON_WANT["cwd"] = 1
  if (!json_parse(tjoin(T, NT))) exit 3
  if (!("tool_input.command" in JSON_GOT)) exit 0
  cmd = JSON_GOT["tool_input.command"]
  if (!gated_text(cmd)) exit 0
  if (length(cmd) > 262144) cmd = gated_lines(cmd)
  cwd = ("cwd" in JSON_GOT) ? JSON_GOT["cwd"] : ""
  if (cwd !~ /^\//) cwd = ENVIRON["CLAUDE_PROJECT_DIR"]
  if (cwd !~ /^\//) cwd = ENVIRON["PWD"]
  analyze(cmd, cwd)
}
