---
description: Diagnose a failure (reproduce, isolate, hypothesize, fix, verify)
agent: ftd
argument-hint: <symptom>
---

Load the `debug` skill and run its loop for this symptom:

$ARGUMENTS

Reproduce it first and capture the exact command and the verbatim error; do not fix what you
cannot trigger. Long runs (flake loops, the suite, `git bisect run`) go to the background. Encode
the cause as a failing test before the fix, then come back to the FTD lane with the evidence.
