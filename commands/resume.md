---
description: Resume an interrupted ASDD run from its session record and progress file
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the most recent session record): $ARGUMENTS

Read the newest `02-DOCS/wiki/sdd/sessions/<date>-<slug>.md`, then
`02-DOCS/wiki/sdd/progress/<slug>.md` and `git log`, and rebuild the state from them, never from
memory: the stage, done and parked tasks, the decision queue, the last verdict. If they disagree
with the working tree, believe the tree and append a correction entry. Say in a few lines where the
run stands and continue from the first task not marked complete, by the phase skill that owns it.
