# hooks/lib/json-get.awk — json_parse(text): a small, complete JSON reader for the hook payload,
# so the hooks need no jq.
#
# Objects, arrays, strings with every escape (\uXXXX and surrogate pairs become UTF-8), numbers
# and literals. Only the string values whose dot path (object keys joined by ".") is a key of
# JSON_WANT are kept, in JSON_GOT[path]; a key of the same name elsewhere (a "command" inside a
# description string, a nested object) is never mistaken for them. Returns 1 when the text is
# valid JSON, else 0. Run with LC_ALL=C so bytes pass through.

function json_parse(text) {
  J_S = text
  J_N = length(J_S)
  J_P = 1
  if (!j_value("")) return 0
  j_ws()
  return J_P > J_N
}

function j_ws(   c) {
  while (J_P <= J_N) {
    c = substr(J_S, J_P, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") J_P++
    else break
  }
}

function j_value(path,   c, rest) {
  j_ws()
  c = substr(J_S, J_P, 1)
  if (c == "{") return j_object(path)
  if (c == "[") return j_array(path)
  if (c == "\"") {
    if (!j_string()) return 0
    if ((path in JSON_WANT) && !(path in JSON_GOT)) JSON_GOT[path] = J_STR
    return 1
  }
  rest = substr(J_S, J_P, 40)
  if (match(rest, /^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)/)) { J_P += RLENGTH; return 1 }
  return 0
}

function j_object(path,   key, c) {
  J_P++
  j_ws()
  if (substr(J_S, J_P, 1) == "}") { J_P++; return 1 }
  while (1) {
    j_ws()
    if (substr(J_S, J_P, 1) != "\"" || !j_string()) return 0
    key = J_STR
    j_ws()
    if (substr(J_S, J_P, 1) != ":") return 0
    J_P++
    if (!j_value(path == "" ? key : path "." key)) return 0
    j_ws()
    c = substr(J_S, J_P, 1)
    J_P++
    if (c == "}") return 1
    if (c != ",") return 0
  }
}

function j_array(path,   c) {
  J_P++
  j_ws()
  if (substr(J_S, J_P, 1) == "]") { J_P++; return 1 }
  while (1) {
    if (!j_value(path "[]")) return 0
    j_ws()
    c = substr(J_S, J_P, 1)
    J_P++
    if (c == "]") return 1
    if (c != ",") return 0
  }
}

# j_string: reads the string at J_P (on its opening quote) into J_STR, decoded.
function j_string(   c, e, code, low, run) {
  J_P++
  J_STR = ""
  while (J_P <= J_N) {
    run = substr(J_S, J_P, 256)
    if (match(run, /^[^"\\]+/)) {
      J_STR = J_STR substr(run, 1, RLENGTH)
      J_P += RLENGTH
      continue
    }
    c = substr(J_S, J_P, 1)
    if (c == "\"") { J_P++; return 1 }
    e = substr(J_S, J_P + 1, 1)
    J_P += 2
    if (e == "n") J_STR = J_STR "\n"
    else if (e == "t") J_STR = J_STR "\t"
    else if (e == "r") J_STR = J_STR "\r"
    else if (e == "b") J_STR = J_STR "\b"
    else if (e == "f") J_STR = J_STR "\f"
    else if (e == "\"" || e == "\\" || e == "/") J_STR = J_STR e
    else if (e == "u") {
      code = j_hex(substr(J_S, J_P, 4))
      if (code < 0) return 0
      J_P += 4
      if (code >= 55296 && code <= 56319 && substr(J_S, J_P, 2) == "\\u") {
        low = j_hex(substr(J_S, J_P + 2, 4))
        if (low >= 56320 && low <= 57343) {
          code = 65536 + (code - 55296) * 1024 + (low - 56320)
          J_P += 6
        }
      }
      J_STR = J_STR j_utf8(code)
    } else return 0
  }
  return 0
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
