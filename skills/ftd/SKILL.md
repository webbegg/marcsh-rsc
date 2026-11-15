---
name: ftd
description: "Use for ordinary authorised change — the default lane once the decisor has ruled out a question and not selected the chain. Keeps one feature document per feature in 02-DOCS holding intent, scope, checklist, evidence and next step, checks tasks off only against observed proof, asks whether to branch before the work writes code, and runs a minimal risk loop (self-check, risk tier, one reviewer from tier 1). NOT the full method (that is `asdd`), NOT the classification itself (that is the decisor in `suggest`), NOT a request for information, which writes nothing."
tags: [ftd, lane, default, feature-document, evidence]
origin: risco
---

# FTD — Fast-Track Development

The lane ordinary work takes. Not a lighter methodology: the **same** discipline about evidence with
none of the coordination `asdd` exists to buy. One document instead of five, written
because the work might be interrupted, not because somebody has to approve it first.

You are here because the decisor in `../suggest/SKILL.md` ruled that this turn authorises a change
and did not select `../asdd/SKILL.md`. If it is still a question, you are in the wrong place: go back
and answer it.

## Why this lane exists

The constitution's seventh principle has said it from the start: *«la fricción es proporcional al
riesgo. Silencio para lo trivial, ceremonia solo donde el fallo es caro. Un sistema que molesta en el
80% inofensivo acaba apagado, y apagado no protege el 20% que importa.»*

The harness spent a long time contradicting it — every request that sounded like building went
through the whole chain. This lane is that principle finally implemented, not a new idea.

## The feature document

One per feature, in the workspace wiki under `02-DOCS/wiki/ftd/<slug>.md`. The workspace root is the
folder that holds `02-DOCS/`; when none exists yet, it is the project folder: create `02-DOCS/` there
and tell the user once that it holds working notes and they may want to add it to `.gitignore`.
Where a workspace folder sits above the code repository, the document goes in the workspace, **never
inside the code repository**: whoever clones it should get code, not somebody else's notes in progress.

It is written **before the first change**, not after, and it holds exactly this:

```markdown
---
author: <who asked for it — git user.name>
branch: <the branch the work runs on>
status: in-progress
---
# <feature>

## Intent          — what changes, and why it is worth doing
## Scope           — what is in, and what is explicitly not
## Checklist       — one line per task, each with what would prove it done
## Evidence        — the observed output per completed task
## Next            — the single next step, so an interruption costs nothing
```

The frontmatter says whose work it is, so «¿qué ha hecho cada uno?» has an answer. When the branch lands
on the default branch, set `status: done` and replace Next with where and when it merged. No hook
does this for you: do it in the landing turn.

No decision journal, no phase records, no approvals. If a decision was meaningful, one line of
rationale goes next to the task it belongs to.

**The checkbox is not the proof.** A task is checked off when its stated check has been *observed* —
the test output, the command's result, the page rendering. A task whose check was skipped, failed or
could not run is recorded as such, honestly. The tenth principle applies here exactly as it does in
the chain: a result asserted without evidence is treated as not done.

## The minimal loop — per change that writes code

The lane inherits ASDD's per-task loop, cut to its floor:

1. **Self-check** — run the change's own check and record the output under Evidence. Focused
   tests run in the foreground; a full suite, build or audit by the long-command rule
   (`../verify/references/generic-gate.md`, "Long commands"). Tell the user they can see the whole
   change with `/diff`, and that `/undo` puts back the files of a turn that went wrong before it
   was committed (`../asdd/references/marcsh.md` §6).
2. **Risk tier** — the tier of what changed, from the path table and content signals in
   `../asdd/references/without-rsc-cli.md` §1. State it in one line with the reason.
3. **Tier ≥ 1 → one fresh-context reviewer**: the `task-reviewer` subagent, with the feature
   document in place of the spec (`../implement/references/per-task-review.md`, which holds the
   inputs and the dispatch). Tier 0 → none.
4. **Mandatory controls** — tests, build, the security scan the project has. What did not run is
   written «not executed», never left blank.

**Escalate to `asdd`** when the risk tier is **2**, or when the change contradicts a decision
already recorded in `decisions.md`: the feature document becomes its spec input, as below.

**The pack's push hook backs this escalation.** It stops a tier-2 branch from being pushed or opened as a PR until a spec linked to it (`branch: <name>` in its frontmatter) passes the spec gate and the panel is recorded: enforced when the pack hooks are on; otherwise held by discipline. Either way you hold the line: at tier 2, do not push or open a PR until that spec exists and passes the gate (`../asdd/references/without-rsc-cli.md` §2). Time pressure does not change the lane: escalate the moment the tier is 2, before writing more code.

## Isolation

rsc records per project whether the default branch is open or closed to the agent. marcsh has no
such switch, so you judge it and ask — never a branch opened on your own (details in
`../asdd/references/without-rsc-cli.md` §6):

- **Default branch looks open** (research, content, scripts, simple projects, no CI, one person) →
  work straight on it. Do not ask about branches.
- **Default branch looks closed** (long-lived code, CI, a deployment or several people, or the user
  said branches and PRs) → before EACH change that writes code, ask with the question tool
  (`../asdd/references/marcsh.md` §3): "Do it on this branch (`<current>`), on a new one, or on
  `<default branch>` directly?", your recommendation first; record the answer in the feature
  document. Already on another branch
  is no exception: an unrelated change does not go into it without asking. A new branch is named by
  intent and closes with a pull request. (In paused AUTO or YOLO approval mode, recommend a worktree: see
  the Approval mode rule in the agent's hard rules.)
- **Docs, wiki or config only** → no question, no branch.
- **Another session working in this same folder** → a separate worktree (`git worktree add
  ../<repo>-<branch> -b <branch>`), never a branch switch under the other session. Only when you can
  see signs of one; alone, setting one up costs more than it protects.

Once the branch lands, remove its worktree and branch only if you created them and they are merged.

## Growing out of the lane

A feature that turns out to need `asdd` is **promoted, not restarted**: the feature document
becomes the input to `../specify/SKILL.md`, and no completed work is discarded. Promotion happens
when durable artifacts would remove a substantial ambiguity, or by the escalation above (tier 2, a
contradicted decision) — never because the work turned out to be big.

## Anti-patterns → STOP

| If you're about to… | Reality / Fix |
| --- | --- |
| Skip the document because the change is small | The document is what survives an interruption. Write it, keep it short. |
| Check a task off because you believe it works | Observed proof or it is not done (P10). Record the check you could not run. |
| Write the document into the code repository | It belongs in `02-DOCS`. A clone should get code, not notes. |
| Open a worktree "to be safe" | That is the chain's ceremony arriving through the back door (P7). |
| Escalate to `asdd` because the change is large | Size never selects it. Only unresolved ambiguity, tier 2, or a contradicted decision. |
| Skip the reviewer because the change looks safe | The tier decides, not the feeling. Tier ≥ 1 gets one. |
| Produce a spec, plan or task artifact here | Those are the chain's. This lane has one document. |

## See Also

- `../suggest/SKILL.md` — the decisor that routes the turn, and the other two lanes.
- `../asdd/SKILL.md` — the full method, for when artifacts genuinely earn their cost.
- `../asdd/references/without-rsc-cli.md` — the risk tier, the spec gate and the branch rules done by hand.
- `../review/SKILL.md` — the reviewer the minimal loop calls at tier ≥ 1.
- `../verify/SKILL.md` — the evidence gate, when this lane's checks need the full battery.
- `../debug/SKILL.md` — a failure to reproduce before fixing; comes back here afterwards.
