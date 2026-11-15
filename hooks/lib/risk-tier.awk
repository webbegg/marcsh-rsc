# hooks/lib/risk-tier.awk — the classifier behind risk-tier (see risk-tier.sh for the input).
#
# Rules: skills/asdd/references/without-rsc-cli.md §1, the same table and signals.
# Input: optional `\001P` section of extra paths (one per line), then `\001D` and unified diffs
# (-U0, --no-renames, so a rename counts on both sides). Paths come from the `diff --git` headers.
# Output: tier=, base=, reason= lines (risk-tier.sh describes them). Run with LC_ALL=C.

function in_set(word, set) { return index(" " set " ", " " word " ") > 0 }

# split_path(p): sets P_N, P_PART[1..P_N] (lower case), P_BASE, P_STEM (before the first dot, or
# the whole name for a dot file) and P_EXT (after the last dot).
function split_path(p,   lp) {
  lp = tolower(p)
  P_N = split(lp, P_PART, "/")
  P_BASE = P_PART[P_N]
  P_STEM = P_BASE
  P_EXT = ""
  if (substr(P_BASE, 1, 1) != "." && index(P_BASE, ".") > 0) P_STEM = substr(P_BASE, 1, index(P_BASE, ".") - 1)
  if (match(P_BASE, /\.[^.]*$/) && RSTART > 1) P_EXT = substr(P_BASE, RSTART + 1)
}

# A folder named like one of set, or a file whose stem is one of them.
function dir_or_stem(set,   i) {
  for (i = 1; i < P_N; i++) if (in_set(P_PART[i], set)) return 1
  return in_set(P_STEM, set)
}

function dir_named(set,   i) {
  for (i = 1; i < P_N; i++) if (in_set(P_PART[i], set)) return 1
  return 0
}

function is_docs(p) {
  split_path(p)
  return dir_named("docs doc") || in_set(P_EXT, "md mdx txt rst") || P_BASE == "license" || P_BASE ~ /^changelog/
}

# classify(p): the tier of the highest row of the path table; sets CLASS.
function classify(p,   lp) {
  split_path(p)
  lp = tolower(p)
  if (P_BASE == ".env" || P_BASE ~ /^\.env\./ || dir_or_stem("secret secrets credential credentials") || in_set(P_EXT, "pem key p12 pfx")) { CLASS = "secrets"; return 2 }
  if (dir_or_stem("auth authn authz login session oauth sso")) { CLASS = "auth"; return 2 }
  if (lp ~ /(^|\/)\.github\/workflows\// || P_BASE == ".gitlab-ci.yml" || P_BASE == "jenkinsfile") { CLASS = "ci"; return 2 }
  if (dir_named("migration migrations")) { CLASS = "migrations"; return 2 }
  if (dir_or_stem("billing payment payments checkout stripe")) { CLASS = "billing"; return 2 }
  if (P_BASE == "claude.md" || P_BASE == "agents.md" || dir_named(".claude")) { CLASS = "agent config"; return 2 }
  if (is_docs(p)) { CLASS = "docs"; return 0 }
  CLASS = "code"
  return 1
}

# Docs, tests, fixtures, lockfiles and minified files: their added lines are not read for the
# auth, billing and migration signals (secrets still count everywhere).
function skip_content(p) {
  if (is_docs(p)) return 1
  split_path(p)
  if (dir_named("test tests __tests__ spec specs e2e fixture fixtures __fixtures__ testdata")) return 1
  if (P_BASE ~ /[._-](test|spec)\.[^.]+$/ || P_BASE ~ /^test_/) return 1
  if (P_EXT == "lock" || in_set(P_BASE, "package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock go.sum")) return 1
  if (P_BASE ~ /\.min\.(js|css)$/) return 1
  return 0
}

function is_comment(line,   t) {
  t = line
  sub(/^[ \t]+/, "", t)
  return t ~ /^(\/\/|#|\/\*|\*|--|<!--)/
}

function add_path(p) {
  if (p == "" || (p in PATHS)) return
  PATHS[p] = 1
  NP++
  PL[NP] = p
}

function hit(cls, signal, f,   key) {
  key = cls SUBSEP signal SUBSEP f
  if (key in SEEN) return
  SEEN[key] = 1
  NHITS++
  HITS[NHITS] = "content " cls " (" signal "): " f
}

function scan(line, f,   l) {
  if (line ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) hit("secrets", "private key block", f)
  if (line ~ AWS_RE) hit("secrets", "AWS access key id", f)
  if (line ~ LIVE_RE) hit("secrets", "live payment key", f)
  if (line ~ GH_RE) hit("secrets", "GitHub token", f)
  if (SKIP[f] || is_comment(line)) return
  l = tolower(line)
  if (l ~ /bcrypt|argon2|scrypt|pbkdf2|password_hash/) hit("auth", "password hash", f)
  if (l ~ /jwt\.(sign|verify)/) hit("auth", "token signing", f)
  if (l ~ /timingsafeequal|createhmac/) hit("auth", "secret comparison", f)
  if (l ~ /passport\.authenticate|getserversession|createsession/) hit("auth", "session", f)
  if (l ~ /set-cookie|setcookie|\.cookie\(|cookies\(\)\.set|cookies\.set/ && l ~ /session|auth|token|jwt/) hit("auth", "session or auth cookie", f)
  if (l ~ /(^|[^a-z0-9_])(paymentintents?|charges?|refunds?|subscriptions?|invoices?)\.(create|update|modify|cancel|confirm|capture|del|delete|pay|finalize)/) hit("billing", "payment call", f)
  if (line ~ /(STRIPE|PAYPAL|BRAINTREE|ADYEN)_[A-Z0-9_]/) hit("billing", "payment key", f)
  if (l ~ /alter[ \t]+table|drop[ \t]+table|drop[ \t]+column|create[ \t]+table|add[ \t]+column|rename[ \t]+column/) hit("migrations", "schema change", f)
}

BEGIN {
  c16 = ""
  for (i = 0; i < 16; i++) c16 = c16 "[0-9A-Z]"
  AWS_RE = "AKIA" c16
  c20 = ""
  for (i = 0; i < 20; i++) c20 = c20 "[0-9A-Za-z]"
  GH_RE = "gh[pousr]_" c20
  LIVE_RE = "[sr]k_live_[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]"
  mode = "D"
}

$0 == "\001P" { mode = "P"; next }
$0 == "\001D" { mode = "D"; next }
mode == "P" { add_path($0); next }

substr($0, 1, 11) == "diff --git " {
  file = ""
  rest = substr($0, 12)
  if (substr(rest, 1, 2) == "a/") {
    rest = substr(rest, 3)
    # rest is "<p> b/<p>" (no renames, so both sides are the same path)
    plen = (length(rest) - 3) / 2
    if (plen == int(plen) && plen > 0 && substr(rest, plen + 1, 3) == " b/") {
      file = substr(rest, 1, plen)
      add_path(file)
    }
  }
  next
}
substr($0, 1, 4) == "--- " || substr($0, 1, 4) == "+++ " {
  p = substr($0, 5)
  if (p != "/dev/null") {
    sub(/^[ab]\//, "", p)
    add_path(p)
    if (file == "") file = p
  }
  if (file != "" && !(file in SKIP)) SKIP[file] = skip_content(file)
  next
}
file != "" && substr($0, 1, 1) == "+" { scan(substr($0, 2), file); next }

END {
  if (NP == 0) { print "tier=none"; print "base=" base; print "reason=nothing to classify"; exit 0 }
  top = 0
  for (i = 1; i <= NP; i++) { T[i] = classify(PL[i]); C[i] = CLASS; if (T[i] > top) top = T[i] }
  if (NHITS > 0) top = 2
  print "tier=" top
  print "base=" base
  shown = 0
  for (i = 1; i <= NP; i++) {
    if (T[i] != top) continue
    shown++
    if (shown <= 20) print "reason=path " C[i] ": " PL[i]
  }
  for (i = 1; i <= NHITS; i++) { shown++; if (shown <= 20) print "reason=" HITS[i] }
  if (shown > 20) print "reason=... and " (shown - 20) " more"
}
