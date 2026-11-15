# hooks/lib/msg-scan.awk — main program for msg-check.awk over a whole input (a message file or
# a `git log --format=%B` dump): prints the first violation and exits 3, else exits 0.
#   awk -f msg-check.awk -f msg-scan.awk < message

{ buf = buf $0 "\n" }

END {
  r = msg_bad(buf)
  if (r != "") { print r; exit 3 }
}
