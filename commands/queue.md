---
description: Show the decision queue and answer its open entries
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the feature in progress): $ARGUMENTS

Read `## Decision queue` in `02-DOCS/wiki/sdd/progress/<slug>.md`. List the open entries, `blocking`
first, one line each with its evidence. Then put each `blocking` entry to the user with the
question tool (its options, your recommendation first), one decision per question, and record each
answer verbatim under its entry. Only the user closes an entry. Then say which parked tasks can
resume.
