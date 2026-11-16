# hooks/lib/secrets.awk — scan the added lines of a unified diff for secrets.
#
#   git diff -U0 ... | awk -f secrets.awk
#
# Prints the hits on one line, `<file>: <kind>; ...` (never the value; at most 10), and exits 3
# when there is one, else 0. Run with LC_ALL=C.
#
# The words are the ship skill's pattern (skills/ship/SKILL.md:51,58: api key, secret, password,
# token, a private key block), narrowed to a literal value being assigned, because the bare words
# match almost any auth code or doc and the ship check is a grep a person reads, not a gate:
#   name = "literal of 8+ chars"   name: 'literal'   NAME=literal-to-end-of-line
# plus the concrete secret signals of skills/asdd/references/without-rsc-cli.md §1 (AWS access
# key id, live payment key, GitHub token). A value read from elsewhere (os.environ[...],
# process.env.X, ${VAR}, a call) is not a hit. A line holding `gitleaks:allow` or
# `pragma: allowlist secret` is skipped, so a deliberate fixture can be marked.

BEGIN {
  v = "[^\"' \t$<{()]"
  v8 = v v v v v v v v
  WORDS = "(api[_-]?key|secret|passwd|password|token)"
  QUOTED_RE = WORDS "[a-z0-9_]*[\"']?[ \t]*(:|=|:=|=>)[ \t]*[\"']" v8 "[^\"' \t$<{()]*[\"']"
  ENV_RE = "^[ \t]*(export[ \t]+)?[a-z0-9_.-]*" WORDS "[a-z0-9_.-]*[ \t]*=[ \t]*" v8 v "*[ \t]*$"
  c16 = ""
  for (i = 0; i < 16; i++) c16 = c16 "[0-9A-Z]"
  AWS_RE = "AKIA" c16
  c20 = ""
  for (i = 0; i < 20; i++) c20 = c20 "[0-9A-Za-z]"
  GH_RE = "gh[pousr]_" c20
  LIVE_RE = "[sr]k_live_[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]"
  file = ""
  n = 0
}

function hit(kind,   key) {
  key = file ": " kind
  if (key in SEEN) return
  SEEN[key] = 1
  n++
  if (n <= 10) out = out (n > 1 ? "; " : "") key
}

substr($0, 1, 4) == "+++ " {
  file = substr($0, 5)
  if (file == "/dev/null") file = ""
  sub(/^b\//, "", file)
  next
}

substr($0, 1, 1) == "+" && file != "" {
  line = substr($0, 2)
  l = tolower(line)
  if (index(l, "gitleaks:allow") || index(l, "pragma: allowlist secret")) next
  if (line ~ /BEGIN [A-Z ]*PRIVATE KEY/) hit("private key block")
  if (line ~ AWS_RE) hit("AWS access key id")
  if (line ~ LIVE_RE) hit("live payment key")
  if (line ~ GH_RE) hit("GitHub token")
  if (l ~ QUOTED_RE || l ~ ENV_RE) hit("hard-coded secret (api key/secret/password/token)")
}

END {
  if (n == 0) exit 0
  print out (n > 10 ? "; ... and " (n - 10) " more" : "")
  exit 3
}
