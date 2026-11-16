# hooks/lib/spec-check.awk — the spec gate of skills/asdd/references/without-rsc-cli.md §2 for the
# specs linked to one branch.
#
#   awk -v want=<branch> -f spec-check.awk 02-DOCS/wiki/sdd/specs/*.md
#
# For every file whose frontmatter has `branch: <want>`, prints
#   PASS<TAB><file>
#   FAIL<TAB><file><TAB>FAIL <slug>: missing section(s): ...; empty section(s): ...
# Checked: every required `## ` section is present and not empty. Empty means nothing under the
# heading, or only the template's guidance: lines holding a `<...>` placeholder (it may span
# lines) or a line that is wholly italic. Not checked (they need judgement): that each point to
# clarify is typed and each acceptance criterion is binary and observable.

BEGIN {
  NREQ = split("Problem & why|Cost of not building it|The cheapest alternative|Goals|Non-goals / out of scope|Users & context|What the user can do|What result they get|What it must respect|How it proves it|Behaviour|Acceptance criteria|Points to clarify", REQ, "|")
  for (i = 1; i <= NREQ; i++) REQKEY[norm(REQ[i])] = i
}

function norm(s) {
  s = tolower(s)
  gsub(/[ \t]+/, " ", s)
  sub(/^ /, "", s)
  sub(/ $/, "", s)
  sub(/:$/, "", s)
  if (s == "behavior") s = "behaviour"
  return s
}

function start_file() {
  file = FILENAME
  branch = ""
  infm = 0
  fmdone = 0
  fence = 0
  cursec = 0
  inph = 0
  split("", PRESENT)
  split("", FILLED)
}

function finish_file(   i, slug, miss, empty, sep1, sep2) {
  if (file == "" || want == "" || branch != want) return
  miss = ""
  empty = ""
  for (i = 1; i <= NREQ; i++) {
    if (!(i in PRESENT)) { miss = miss sep1 REQ[i]; sep1 = ", " }
    else if (!(i in FILLED)) { empty = empty sep2 REQ[i]; sep2 = ", " }
  }
  if (miss == "" && empty == "") { print "PASS\t" file; return }
  slug = file
  sub(/.*\//, "", slug)
  sub(/\.md$/, "", slug)
  print "FAIL\t" file "\tFAIL " slug ": missing section(s): " (miss == "" ? "none" : miss) "; empty section(s): " (empty == "" ? "none" : empty)
}

# content(line): 1 when the line has text that is not template guidance. Tracks `<...>` spans.
function content(line,   i, c, n, outside, touched) {
  n = length(line)
  outside = 0
  touched = inph
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (inph) { if (c == ">") inph = 0; continue }
    if (c == "<" && i < n && substr(line, i + 1, 1) != " ") { inph = 1; touched = 1; continue }
    if (c ~ /[A-Za-z0-9]/) outside = 1
  }
  if (touched) return 0
  if (line ~ /^[ \t]*\*[^*].*\*[ \t]*$/ || line ~ /^[ \t]*_[^_].*_[ \t]*$/) return 0
  return outside
}

FNR == 1 { finish_file(); start_file() }

FNR == 1 && $0 == "---" { infm = 1; next }
infm {
  if ($0 == "---") { infm = 0; next }
  if ($0 ~ /^branch:/) {
    v = $0
    sub(/^branch:[ \t]*/, "", v)
    sub(/[ \t]+$/, "", v)
    if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
    branch = v
  }
  next
}

/^[ \t]*(```|~~~)/ { fence = !fence; if (cursec) FILLED[cursec] = 1; next }
fence { if (cursec && $0 ~ /[A-Za-z0-9]/) FILLED[cursec] = 1; next }

/^##?[ \t]/ {
  inph = 0
  cursec = 0
  if ($0 ~ /^##[ \t]/) {
    h = $0
    sub(/^##[ \t]+/, "", h)
    k = norm(h)
    if (k in REQKEY) { cursec = REQKEY[k]; PRESENT[cursec] = 1 }
  }
  next
}

/^###/ { next }

cursec && content($0) { FILLED[cursec] = 1 }

END { finish_file() }
