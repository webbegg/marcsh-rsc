---
description: Show the decision queue and answer its open entries
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the feature in progress): $ARGUMENTS

Read `## Decision queue` in `02-DOCS/wiki/sdd/progress/<slug>.md`. List the open entries, `blocking`
first, one line each with its evidence. Then put each `blocking` entry to the user with the
question tool (its options, your recommendation first), one decision per question. For each
answer, record it verbatim on an indented line under its entry, then change only the entry's tag
from `[blocking]` to `[closed]`: the one edit allowed to an old line of the progress file. Only
the user's answer closes an entry. Then say which parked tasks can resume.
