---
description: Write a spec for an idea (specify, then clarify, then your approval)
agent: asdd
argument-hint: <idea>
---

Load the `specify` skill and run its pass for this idea:

$ARGUMENTS

Restate it and give the strongest objection, offer autopilot once, ask the frontier with the
question tool, write `02-DOCS/wiki/sdd/specs/<slug>.md` (with `branch:` in its frontmatter once the
work has a branch), run the spec gate and, when the stakes call for it, the `spec-reviewer`
subagent. Then load `clarify` for its gaps, and ask for approval of the revised spec as its own
question. Do not plan or write code.
