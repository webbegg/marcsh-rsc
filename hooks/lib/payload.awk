# hooks/lib/payload.awk — main program of the hook's one awk pass:
#
#   awk -f json-get.awk -f msg-check.awk -f parse-command.awk -f payload.awk < payload.json
#
# Reads the PreToolUse payload, takes tool_input.command and cwd (falling back to
# $CLAUDE_PROJECT_DIR, then $PWD) and prints the gated calls (parse-command.awk's format).
# Exit 0 (nothing printed: nothing to check), or 3 when the payload is not valid JSON.

{ text = text $0 "\n" }

END {
  JSON_WANT["tool_input.command"] = 1
  JSON_WANT["cwd"] = 1
  if (!json_parse(text)) exit 3
  if (!("tool_input.command" in JSON_GOT)) exit 0
  cmd = JSON_GOT["tool_input.command"]
  if (index(cmd, "git") == 0 && index(cmd, "gh") == 0) exit 0
  cwd = ("cwd" in JSON_GOT) ? JSON_GOT["cwd"] : ""
  if (cwd !~ /^\//) cwd = ENVIRON["CLAUDE_PROJECT_DIR"]
  if (cwd !~ /^\//) cwd = ENVIRON["PWD"]
  analyze(cmd, cwd)
}
