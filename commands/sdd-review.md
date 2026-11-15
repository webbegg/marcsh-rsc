---
description: Review one task (by its tier) or the whole branch against the spec
agent: asdd
argument-hint: "[spec slug | T<n>]"
---

Target (a task id like `T004` reviews that task; a spec slug or nothing runs the closing review of
the current branch): $ARGUMENTS

Load the `review` skill. Compute the risk tier from the diff, then start the subagents it names
(`task-reviewer` at tier 1, `refuter-correctness`, `refuter-security` and `refuter-tests` at tier
2) with exactly their inputs, consolidate their findings, verify every blocker and should-fix with
`finding-verifier`, and record the rounds and outcomes. End with the verdict.
