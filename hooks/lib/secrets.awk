# hooks/lib/secrets.awk — scan the added lines of a unified diff for secrets.
#
#   git diff -U0 ... | awk -f secrets.awk
#
# Prints the hits on one line, `<file>: <kind>; ...` (never the value; at most 10), and exits 3
# when there is one, else 0. Run with LC_ALL=C.
#
# With -v multi=1 the input is `git diff-tree --stdin -p` output, where a commit id line starts
# the diff of that commit: one `<id><TAB><hits>` line per diff with hits (exit 3 when any).
#
# Two kinds of hit, so that ordinary code is not blocked:
# 1. A concrete key format, anywhere: AWS access key id (AKIA/ASIA), GitHub token (ghp_ gho_ ghu_
#    ghs_ ghr_ github_pat_), Slack token (xoxa- xoxb- xoxp- xoxr- xoxs-), live Stripe key
#    (sk_live_ rk_live_), a private key block, a JWT (eyJ...\.eyJ...\....), a Google API key (AIza).
# 2. A literal assigned to a secret-looking name (the ship skill's words, skills/ship/SKILL.md:51:
#    password, passwd, secret, token, api key). The name, split into words at `_`, `-` and
#    camelCase, has one of those words as a whole word (db_password, API_KEY, clientSecret; not
#    tokenizer, totalTokens). The value is a quoted string literal (`= :  := => ??= ||=`) of 12 or
#    more characters that is not a URL, a path, prose (has blanks), an identifier made of words
#    (client_secret_basic, bert-base-uncased) or a placeholder (<...>, ${...}, {{...}}, xxx,
#    changeme, example, dummy, test, placeholder, redacted). In an env file (`*.env`, `.env*`) an
#    unquoted `NAME=value` counts too, with any non-empty value that is not a placeholder or $VAR.
# A value read from elsewhere (os.environ[...], process.env.X, a variable, a call) is never a
# hit. A line holding `gitleaks:allow` or `pragma: allowlist secret` is skipped, so a deliberate
# fixture can be marked.

function rep(cls, n,   s, i) {
  s = ""
  for (i = 0; i < n; i++) s = s cls
  return s
}

BEGIN {
  AWS_RE = "(AKIA|ASIA)" rep("[0-9A-Z]", 16)
  GH_RE = "gh[pousr]_" rep("[0-9A-Za-z]", 20)
  GHPAT_RE = "github_pat_" rep("[0-9A-Za-z_]", 22)
  SLACK_RE = "xox[abprs]-" rep("[0-9A-Za-z-]", 10)
  LIVE_RE = "[sr]k_live_" rep("[0-9A-Za-z]", 8)
  b64 = "[0-9A-Za-z_-]"
  JWT_RE = "eyJ" rep(b64, 10) b64 "*\\.eyJ" rep(b64, 10) b64 "*\\." rep(b64, 10)
  GOOG_RE = "AIza" rep(b64, 35)
  file = ""
  n = 0
}

# flush(): the hit line of the diff of commit sect (multi), then a fresh state for the next one.
function flush() {
  if (n > 0) {
    print sect "\t" out (n > 10 ? "; ... and " (n - 10) " more" : "")
    any = 1
  }
  n = 0
  out = ""
  file = ""
  envfile = 0
  split("", SEEN)
}

function hit(kind,   key) {
  key = file ": " kind
  if (key in SEEN) return
  SEEN[key] = 1
  n++
  if (n <= 10) out = out (n > 1 ? "; " : "") key
}

# secret_name(name): the last dotted part of name has a secret word as a whole word.
function secret_name(name,   len, i, c, prev, nx, s, P, m) {
  sub(/.*\./, "", name)
  len = length(name)
  if (len == 0 || len > 64) return 0
  s = ""
  for (i = 1; i <= len; i++) {
    c = substr(name, i, 1)
    if (i > 1 && c ~ /[A-Z]/) {
      prev = substr(name, i - 1, 1)
      nx = substr(name, i + 1, 1)
      if (prev ~ /[a-z0-9]/ || (prev ~ /[A-Z]/ && nx ~ /[a-z]/)) s = s "_"
    }
    s = s c
  }
  m = split(tolower(s), P, "[_-]+")
  for (i = 1; i <= m; i++) {
    if (P[i] ~ /^(password|passwd|secret|token|apikey)$/) return 1
    if (P[i] == "api" && P[i + 1] == "key") return 1
  }
  return 0
}

function placeholder(v,   l) {
  l = tolower(v)
  if (index(v, "<") || index(v, "${") || index(v, "{{") || index(v, "%(") || index(v, "%s")) return 1
  return l ~ /xxx|changeme|example|dummy|test|placeholder|redacted|\*\*\*/
}

function secret_value(v) {
  if (length(v) < 12) return 0
  if (tolower(v) ~ /^[a-z][a-z0-9+.-]*:\/\//) return 0
  if (v ~ /^(\/|\.\.?\/|~\/)/) return 0
  if (v ~ /[ \t]/) return 0
  if (v ~ /^[A-Za-z]+([_.-][A-Za-z]+)+$/) return 0
  return !placeholder(v)
}

function scan_assign(line,   rest, m, name, v, cnt) {
  rest = line
  cnt = 0
  while (cnt < 50 && match(rest, /[A-Za-z0-9_.-]+["']?[ \t]*(:=|=>|\?\?=|\|\|=|=|:)[ \t]*("[^"]*"|'[^']*')/)) {
    m = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    cnt++
    match(m, /^[A-Za-z0-9_.-]+/)
    name = substr(m, 1, RLENGTH)
    sub(/^[A-Za-z0-9_.-]+["']?[ \t]*(:=|=>|\?\?=|\|\|=|=|:)[ \t]*/, "", m)
    v = substr(m, 2, length(m) - 2)
    if (secret_name(name) && secret_value(v)) return 1
  }
  return 0
}

function scan_env(line,   name, v) {
  if (!match(line, /^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=/)) return 0
  name = substr(line, 1, RLENGTH - 1)
  v = substr(line, RLENGTH + 1)
  sub(/^[ \t]*(export[ \t]+)?/, "", name)
  sub(/[ \t]+$/, "", name)
  sub(/^[ \t]+/, "", v)
  sub(/[ \t]+#.*$/, "", v)
  sub(/[ \t\r]+$/, "", v)
  if (v == "" || v ~ /^["'$]/) return 0
  return secret_name(name) && !placeholder(v)
}

multi && (length($0) == 40 || length($0) == 64) && $0 !~ /[^0-9a-f]/ { flush(); sect = $0; next }

substr($0, 1, 4) == "+++ " {
  file = substr($0, 5)
  if (file == "/dev/null") file = ""
  sub(/^b\//, "", file)
  base = file
  sub(/.*\//, "", base)
  envfile = (base ~ /^\.env/ || base ~ /\.env$/)
  next
}

substr($0, 1, 1) == "+" && file != "" {
  line = substr($0, 2)
  l = tolower(line)
  if (index(l, "gitleaks:allow") || index(l, "pragma: allowlist secret")) next
  if (line ~ /BEGIN [A-Z ]*PRIVATE KEY/) hit("private key block")
  if (line ~ AWS_RE) hit("AWS access key id")
  if (line ~ LIVE_RE) hit("live payment key")
  if (line ~ GH_RE || line ~ GHPAT_RE) hit("GitHub token")
  if (line ~ SLACK_RE) hit("Slack token")
  if (line ~ JWT_RE) hit("JWT")
  if (line ~ GOOG_RE) hit("Google API key")
  if (scan_assign(line) || (envfile && scan_env(line))) hit("hard-coded secret (api key/secret/password/token)")
}

END {
  if (multi) {
    flush()
    exit any ? 3 : 0
  }
  if (n == 0) exit 0
  print out (n > 10 ? "; ... and " (n - 10) " more" : "")
  exit 3
}
