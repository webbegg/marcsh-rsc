---
description: Build an approved plan task by task (implement), resuming from the progress file
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the feature in progress; if several fit, ask which with the question
tool): $ARGUMENTS

Load the `implement` skill and run its gate, then the per-task loop. Resume from
`02-DOCS/wiki/sdd/progress/<slug>.md` and `git log`, never from memory: a task recorded
`status: complete` is done and is not dispatched again. Review by tier with the pack's subagents
(`task-reviewer`, or the three refuters at tier 2), run long commands in the background, and park
what must not be decided alone in the decision queue.
