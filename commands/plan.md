---
description: Plan an approved spec (plan, tasks, analyze)
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the most recent approved spec; if several fit, ask which with the question
tool): $ARGUMENTS

Check that the spec is approved; if it is not, say so and route to `specify` or `clarify`. Then
load `plan` and write the plan, propose isolating the work on its own branch, load `tasks` to
append the task list and its review workload forecast, and load `analyze` to cross-read
constitution, spec, plan and tasks. Stop at the analyze report.
