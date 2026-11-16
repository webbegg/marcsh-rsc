# Per-task review — the tier-1 reviewer

The one fresh-context reviewer a **tier-1** task gets (step c of `implement`'s loop; FTD's minimal
loop uses it too). Tier 2 uses the three lenses as `../../review/SKILL.md` runs them.

**The brief is frozen in the `task-reviewer` subagent** (`../../../agents/task-reviewer.md`): its
inputs, the two verdicts it returns (spec compliance, code quality), the findings JSON, the
`VERDICT:` line and the anti-pre-judging rules. Never re-express it at dispatch; the orchestrator's
paraphrase is exactly the bias that file guards against.

## Dispatch

Start the `task-reviewer` subagent with `Task` (`agent: "task-reviewer"`); give it exactly the
inputs listed. To run several at once on pi use `background: true` and collect them with
`task_wait` (cancel with `task_cancel`); on Claude issue the `Task` calls in parallel. If `Task`
has no `agent` parameter (older marcsh), pass the subagent file's body as the prompt instead. Only
when no subagent can be started at all, run the pass yourself and record that it was not
independent. (On pi, start even a single reviewer with `background: true` when the session offers
it: a foreground `Task` is stopped after 3 minutes. Details: `../../asdd/references/marcsh.md` §2.)

## Inputs to hand the reviewer (paths and values, not prose)

- **The approved spec** (`02-DOCS/wiki/sdd/specs/<slug>.md`), or the FTD feature document.
- **The diff**, as a file: the path printed by `scripts/review-package <BASE> <HEAD>` (BASE = the
  task's recorded base sha; from fix round 2, the previous round's head). The diff never enters the
  orchestrator's context.
- **The surrounding code** at HEAD: the reviewer reads the files the diff touches.
- **The done-check**, the task's **Interfaces → `Produces`**, and the plan's **§0 Global
  Constraints**.

Nothing else: never your session reasoning, and never a word about what not to flag or how severe
something is.

## What comes back

Findings in `review`'s format and severities, ending with a ` ```json findings ` block (the input
to consolidation and the ledger, `../../asdd/references/without-rsc-cli.md` §3–4) and one line
`VERDICT: pass` or `VERDICT: changes-needed (<counts>)`. A `blocker` or `should-fix` without
`file`+`line` or `failure_scenario` is downgraded to `question` when the reports are grouped; every
remaining blocker and should-fix is then verified (`../../review/SKILL.md`, "Consolidate, then
verify"). Zero findings is a valid outcome.
