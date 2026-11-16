---
description: Run an ordinary change through FTD (lane, feature document, minimal risk loop)
agent: ftd
argument-hint: <what to change>
---

Load the `ftd` skill and follow it for this request:

$ARGUMENTS

First name the lane in one line (answer, FTD, or ASDD) by the `suggest` decisor. For FTD, write the
feature document at `02-DOCS/wiki/ftd/<slug>.md` before the first change, ask where the work runs
when you are on the default branch (a new branch or a worktree; marcsh blocks commits there), then run the minimal loop: self-check, risk tier, the
`task-reviewer` subagent from tier 1, mandatory controls. Escalate to ASDD at tier 2.
