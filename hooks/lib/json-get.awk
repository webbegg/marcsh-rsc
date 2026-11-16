# hooks/lib/json-get.awk — json_parse(text): a small, complete JSON reader for the hook payload,
# so the hooks need no jq. Also tjoin(A, n), shared by the other awk files of the hook.
#
# Objects, arrays, strings with every escape (\uXXXX and surrogate pairs become UTF-8), numbers
# and literals. Only the string values whose dot path (object keys joined by ".") is a key of
# JSON_WANT are kept, in JSON_GOT[path]; a key of the same name elsewhere (a "command" inside a
# description string, a nested object) is never mistaken for them. Returns 1 when the text is
# valid JSON, else 0. Run with LC_ALL=C so bytes pass through.
#
# Linear in the payload size: some awks (the BWK awk of macOS) pay strlen() of the whole string on
# every substr() and are super-linear on a split() at a regex, so the structure is read through a
# 1 KB window of the text (slid forward, one substr of the whole text per KB). A string is found
# by splitting 64 KB chunks at quotes (the closing quote is the first one after an even number of
# backslashes), then decoded by splitting it at backslashes (one-character splits are linear),
# and strings are built from pieces joined eight at a time (tjoin), never by appending to one
# growing string.

# tjoin(A, n) — A[1] A[2] ... A[n], joined eight at a time in O(total log n). Clobbers A.
function tjoin(A, n,   i, j, s) {
  if (n <= 0) return ""
  while (n > 1) {
    j = 0
    for (i = 1; i + 7 <= n; i += 8) A[++j] = A[i] A[i + 1] A[i + 2] A[i + 3] A[i + 4] A[i + 5] A[i + 6] A[i + 7]
    if (i <= n) {
      s = A[i]
      for (i++; i <= n; i++) s = s A[i]
      A[++j] = s
    }
    n = j
  }
  return A[1]
}

function json_parse(text) {
  J_S = text
  J_N = length(J_S)
  J_P = 1
  J_WB = 1
  J_WN = 0
  J_W = ""
  if (!j_value("")) return 0
  j_ws()
  return J_P > J_N
}

# j_win: makes the window J_W (starting at text position J_WB) cover J_P and the 48 characters
# after it, when the text has them. j_off: J_P's index inside the window.
function j_win() {
  if (J_P < J_WB || (J_P + 48 > J_WB + J_WN && J_WB + J_WN <= J_N)) {
    J_WB = J_P
    J_W = substr(J_S, J_P, 1024)
    J_WN = length(J_W)
  }
  return J_P - J_WB + 1
}

function j_c(   o) {
  o = j_win()
  return substr(J_W, o, 1)
}

function j_ws(   c, o) {
  while (J_P <= J_N) {
    o = j_win()
    c = substr(J_W, o, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") J_P++
    else break
  }
}

function j_value(path,   c, rest, o, keep) {
  j_ws()
  o = j_win()
  c = substr(J_W, o, 1)
  if (c == "{") return j_object(path)
  if (c == "[") return j_array(path)
  if (c == "\"") {
    keep = 0
    if ((path in JSON_WANT) && !(path in JSON_GOT)) keep = 1
    if (!j_string(keep)) return 0
    if (keep) JSON_GOT[path] = J_STR
    return 1
  }
  rest = substr(J_W, o, 40)
  if (match(rest, /^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)/)) { J_P += RLENGTH; return 1 }
  return 0
}

function j_object(path,   key, c) {
  J_P++
  j_ws()
  if (j_c() == "}") { J_P++; return 1 }
  while (1) {
    j_ws()
    if (j_c() != "\"" || !j_string(1)) return 0
    key = J_STR
    j_ws()
    if (j_c() != ":") return 0
    J_P++
    if (!j_value(path == "" ? key : path "." key)) return 0
    j_ws()
    c = j_c()
    J_P++
    if (c == "}") return 1
    if (c != ",") return 0
  }
}

function j_array(path,   c) {
  J_P++
  j_ws()
  if (j_c() == "]") { J_P++; return 1 }
  while (1) {
    if (!j_value(path "[]")) return 0
    j_ws()
    c = j_c()
    J_P++
    if (c == "]") return 1
    if (c != ",") return 0
  }
}

# j_string(keep): reads the string at J_P (on its opening quote); when keep, decoded into J_STR.
# Returns 0 when it is not terminated or has an invalid escape.
function j_string(keep,   start, p, c, m, Q, i, bs, total, carry, s) {
  J_P++
  start = J_P
  p = J_P
  carry = 0
  while (p <= J_N) {
    c = substr(J_S, p, 65536)
    m = split(c, Q, "\"")
    total = 0
    for (i = 1; i < m; i++) {
      total += length(Q[i])
      bs = match(Q[i], /\\+$/) ? RLENGTH : 0
      if (i == 1 && bs == length(Q[1])) bs += carry
      if (bs % 2 == 0) {
        J_P = p + total + 1
        s = j_decode(substr(J_S, start, p + total - start))
        if (J_BAD) return 0
        if (keep) J_STR = s
        return 1
      }
      total++
    }
    bs = match(Q[m], /\\+$/) ? RLENGTH : 0
    if (m == 1 && bs == length(Q[1])) bs += carry
    carry = bs
    p += length(c)
  }
  return 0
}

# j_decode(raw): the JSON escapes of raw decoded (J_BAD = 1 on an invalid one). Split at the
# backslashes: each piece after one starts with its escape letter, except the piece after an
# escaped backslash (an empty piece), which is plain text.
function j_decode(s,   n, A, i, a, e, code, low, plain) {
  J_BAD = 0
  if (!index(s, "\\")) return s
  if (!("n" in J_ESC)) {
    J_ESC["n"] = "\n"; J_ESC["t"] = "\t"; J_ESC["r"] = "\r"; J_ESC["b"] = "\b"
    J_ESC["f"] = "\f"; J_ESC["\""] = "\""; J_ESC["/"] = "/"
  }
  n = split(s, A, "\\")
  plain = 0
  for (i = 2; i <= n; i++) {
    if (plain) { plain = 0; continue }
    a = A[i]
    e = substr(a, 1, 1)
    if (e in J_ESC) { A[i] = J_ESC[e] substr(a, 2); continue }
    if (a == "") {
      if (i == n) { J_BAD = 1; return "" }
      A[i] = "\\"
      plain = 1
      continue
    }
    code = (e == "u") ? j_hex(substr(A[i], 2, 4)) : -1
    if (code < 0) { J_BAD = 1; return "" }
    if (code >= 55296 && code <= 56319 && length(A[i]) == 5 && i < n && substr(A[i + 1], 1, 1) == "u") {
      low = j_hex(substr(A[i + 1], 2, 4))
      if (low >= 56320 && low <= 57343) {
        A[i] = j_utf8(65536 + (code - 55296) * 1024 + (low - 56320)) substr(A[i + 1], 6)
        A[++i] = ""
        continue
      }
    }
    A[i] = j_utf8(code) substr(A[i], 6)
  }
  return tjoin(A, n)
}

function j_hex(h,   i, d, v) {
  if (length(h) != 4) return -1
  v = 0
  for (i = 1; i <= 4; i++) {
    d = index("0123456789abcdef", tolower(substr(h, i, 1)))
    if (d == 0) return -1
    v = v * 16 + d - 1
  }
  return v
}

function j_utf8(c) {
  if (c == 0) return ""
  if (c < 128) return sprintf("%c", c)
  if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
  if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
  return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64)
}
