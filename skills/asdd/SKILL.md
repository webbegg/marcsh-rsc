---
name: asdd
description: "Use when a feature or substantial change should go from idea to shipped, verified software and an agent may run it for hours on its own — the ASDD (Agent Spec-Driven Development) dispatcher and front door, in any language. A spec that must prove itself, review inside every task scaled by the risk tier, a decision queue for what the agent must not decide alone. Routes constitution -> specify -> clarify -> plan -> tasks -> analyze -> implement (verify + review per task) -> closing -> ship. Successor of `sdd`. NOT a single phase (it dispatches), NOT small authorised changes (that is `ftd`), NOT the rsc workspace harness (not part of this pack)."
tags: [sdd, asdd, spec, workflow, plan, review]
origin: risco
---

# asdd — Agent Spec-Driven Development

*The front door for letting an agent build for hours without coming back with a Frankenstein: intent in, shipped-and-verified software out, every decision recorded in `02-DOCS/wiki/sdd/`.*

**Why it exists.** Classic SDD reviewed at the end. On paper it checked the spec; in a long autonomous run, the only thing that bit for hours was the test — and tests prove the code works, not that it does what was asked (a real run: 8 hours, 4,500 green tests, and a dropped token plus a QR nobody requested). ASDD keeps the phases and changes two things: **the spec must prove itself**, and **the review moves inside every task**, scaled by risk. The human stops reviewing everything and only takes the decisions the agent must not take alone.

This skill does **not** do a phase. It names the method, reads the register, places the request on the map and hands off. Each phase skill points at the next one.

**Running under marcsh.** This pack is adapted from the rsc harness, which wraps these skills in a command line tool and hooks. This pack installs no tool; every check the text names (`rsc risk`, `spec gate`, `review ledger`, `sello`, branch guards) has a manual equivalent in `references/without-rsc-cli.md`; read it once before the first phase and use it wherever a skill names an rsc call. The pack ships its own hooks for the tier-2 push, PR and merge gates, the blocking queue, authorship and secrets: enforced when the pack hooks are on; otherwise held by discipline. `references/marcsh.md` says how the chain uses marcsh: long commands in the background, the named reviewer and worker subagents, the question tool, the hooks, the approval mode, and `/diff`, `/undo`, `/export`, `/compact`.

## The five stages

```text
  request ─► decisor (answer · ftd · asdd)
                         │ asdd
 1. BASE ─────► constitution + REVIEW.md                 (once per project)
 2. SPEC ─────► specify (4 questions + out of scope) ─► clarify (gap checklist)   ◄── HUMAN APPROVES
 3. PLAN ─────► plan ─► tasks (criterion · risk forecast · check) ─► analyze
 4. LOOP ─────► per task, in implement:
                 a build + self-check   b risk tier       c review by tier
                 d verify findings      e mandatory controls
                 f fix (max 3 rounds)   g fix & record  ─or─  park ─► DECISION QUEUE ◄── HUMAN
 5. CLOSE ────► verify against main + rollback plan · closing review (whole branch vs spec) · explainer
    SHIP ─────► remote: PR (self-merge only tier 0-1 + green CI + no blocking entry)  │  no remote: park  ◄── HUMAN
    LEARN ────► finding outcomes · reverts → reviewer cases · repeated finding → rule
```

| Stage | Phase skills | Writes |
| --- | --- | --- |
| **1 Base** | `../constitution/SKILL.md` (also drafts `REVIEW.md`) | `constitution.md`, `REVIEW.md` |
| **2 Spec** | `../specify/SKILL.md` → `../clarify/SKILL.md` | `specs/<slug>.md` |
| **3 Plan** | `../plan/SKILL.md` → `../tasks/SKILL.md` → `../analyze/SKILL.md` | `plans/<slug>.md`, `analysis/<slug>.md` |
| **4 Loop** | `../implement/SKILL.md`, calling `../verify/SKILL.md` and `../review/SKILL.md` per task | `progress/<slug>.md` (with `## Decision queue`), `decisions.md` |
| **5 Close** | `../verify/SKILL.md` (closing mode), then `../review/SKILL.md` (closing review, on what will ship), `../ship/SKILL.md` | `verifications/<slug>-<date>.md`, `reviews/<slug>.md`, the PR or parked branch |
| on demand | `../debug/SKILL.md` | — |

**Where the human enters — three places only:** approving the spec, answering the decision queue, approving a tier-2 merge. Everything else runs.

No ASDD phase edits the project's agent instruction files (`CLAUDE.md`, `AGENTS.md`): every artifact is indexed in `02-DOCS/wiki/index.md` (the Knowledge map; create it on first use). Those files are tier 2 in the risk table.

### The spec proves itself

Every spec answers four questions, and the spec gate (`references/without-rsc-cli.md` §2) refuses one dated 2026-11-03 or later without them: **what the user can do**, **what result they get** (against a reference the human approved — a screenshot, a sketch, an expected API response), **what it must respect** (prior decisions, specs and behaviour; read from the brain when the project has one, else `decisions.md`), **how it proves it** (how the check runs, what evidence remains — "yes, I tested it" is not evidence). Plus an explicit **out of scope**: what the agent might add "just in case".

### The risk decides, never the agent

The risk tier classifies a change by **what it touches and what it adds** (a path table plus fixed content patterns — password hashing, session cookies, payments, schema changes, secrets — so auth code in `src/app.js` is still auth). The table and the procedure are in `references/without-rsc-cli.md` §1: tier 0 docs/copy → no reviewer; tier 1 ordinary code → one fresh-context reviewer; tier 2 auth, billing, CI workflows, migrations, secrets, agent config → the three-lens panel **and human approval**. An agent's approval never counts as a human's. A tier-2 branch is stopped at push unless a linked spec passes the gate and a panel is recorded: enforced when the pack hooks are on; otherwise held by discipline. Either way **you** hold that line: no push, PR or merge at tier 2 until the spec passes the gate, the three lenses ran and are recorded in the progress file, and the user said yes.

### The loop converges

The review ledger holds it to the rules that stopped Anthropic's 50-round reviews: a 4th round on a task is refused (rethink the approach or park the task), a finding already raised is a `repeat` that is never raised again, each finding closes as `fixed|false|intentional|irrelevant|parked`. Keep the ledger by hand in the progress file (`references/without-rsc-cli.md` §3). Flag the bug class, not the line; from round 2 re-review only the new diff.

### Park, don't block

Tier 2, a contradiction with a recorded decision, a gap that would make the build unsafe, or no convergence in 3 rounds: the task goes to the **decision queue** (`## Decision queue` in `progress/<slug>.md`) with its evidence, and the agent **continues with the independent tasks**. The run never waits at 2 a.m. for an answer.

Every entry carries a kind, one line each, in exactly this form (no bold, no other bullet; the pack's merge hook greps for `- [blocking]`):

```markdown
- [blocking] Q3 — <what must be decided>, <evidence>, <task>
- [review-after] Q4 — <assumption taken>, <where it is recorded>, <task>
```

- **`blocking`** — tier 2, a contradiction with a recorded decision, no convergence in 3 rounds, a hard failure. It stops a self-merge.
- **`review-after`** — clarify's recorded assumptions, a spec reference the agent had to write itself, a provisional constitution ratification. It never stops a merge; it is listed in the PR body (or the parked summary) for the human.

## The invoke rule — route to the phase that fits

> **The new-feature gate (hard).** The moment the user is thinking about a new feature or change — "add…", "build…", "it should also…", "quiero añadir…" — and the decisor chose this lane, it goes to `specify` first, *even if a stack skill also fired*. **No feature code is written — by any skill — until a spec AND a plan exist and are approved.** Small authorised changes go to `../ftd/SKILL.md`, which escalates here when `rsc risk` says tier 2 or the change contradicts a recorded decision.

1. **Empty repo (nothing to detect)?** → `constitution` first (it decides the stack).
2. **First ASDD run in this project?** Create `02-DOCS/wiki/sdd/` and its index row; no config file is needed. **No constitution, or `status: draft`?** → `constitution` once (it also drafts `REVIEW.md`).
3. **Ambiguous / architectural / risky before a spec?** → optional proposal via `specify`.
4. **Fuzzy idea, no spec?** → `specify`. **Spec with gaps?** → `clarify`.
5. **Approved spec, no plan?** → `plan`, then `tasks`, then `analyze`.
6. **Green light?** → `implement` (the per-task loop; `developer` subagents for disjoint `[P]` tasks, or a separate worktree when another session shares the folder).
7. **All tasks done or parked?** → closing: `verify` (closing mode, main merged in), then `review` (closing review of that exact state), then `ship`.
8. **Broken mid-flight?** → `debug`, then resume.

Cannot tell the phase? Ask one question with the question tool (`references/marcsh.md` §3): *"Do we have a written spec for this yet?"*, options "No, start from the idea", "Yes, it needs clarifying", "Yes, it is approved".

Skip honestly: `constitution` runs once per project; `clarify` and `analyze` are gates, not paperwork — pass through only when the change is genuinely tiny, and say so.

## Autopilot — one up-front yes

The user says "take it all the way" once and the chain runs end to end **without asking to continue between phases**, still writing every artifact. The up-front yes satisfies the new-feature gate.

Autopilot does not stop the run for questions — it **parks**: real ambiguity, tier 2, a contradiction with a recorded decision or a non-converging task go to the decision queue while independent work continues. It **stops** only for a hard failure nothing else can proceed past, and for destructive or irreversible actions.

**In autopilot, per phase:**

- `constitution` ratifies provisionally → `review-after` entry.
- `specify` uses a checkable reference it wrote itself (expected output, sample response) → `review-after` entry.
- `clarify` records its assumptions (`suposición tomada`) → `review-after` entries.
- `implement` parks `blocking` items and continues with the independent tasks.
- `ship` lands by the rule below.

**Never hand the turn back mid-run.** No "¿sigo?" / "shall I continue?": not between phases, not while reviewers run. Background reviewers and workers are waited for with `task_wait` (call it again until each result is in), and background commands are collected from their result; ending the turn to wait ends a headless run. A later "continue" from the person resumes the run; it is **not** approval for a tier-2 merge, which needs an explicit yes to that merge.

**Landing — there is always a legal path.** A remote exists → open a PR; self-merge only when the risk tier is 0-1, CI is green and no `blocking` entry is open; `review-after` entries go into the PR body. No remote → **park**: leave the branch committed, write the explainer, the open entries and the exact merge command for the human into `progress/<slug>.md`, and stop. Never merge locally into a default branch the project protects (`references/without-rsc-cli.md` §6): park instead.

Narrate plainly: name each stage as it passes and show its artifact, one line each.

## Read the register first

Read `technical_level` in `02-DOCS/wiki/harness/user-profile.md` if the file exists. It picks the words (technical, or plain with analogies), never whether the gates exist. No profile → ask once with the question tool, "technical terms or analogies?", and if the answer should last, write it to that file as `technical_level: technical | non-technical`. At gates, ask only what changes what gets built, one question at a time, recommendation first, with the question tool, and record the answer verbatim where the phase skill says.

## Where the artifacts live

```text
02-DOCS/wiki/sdd/
├── constitution.md          ← non-negotiables (once)
├── proposals/<slug>.md      ← optional pre-execution briefing
├── specs/<slug>.md          ← one spec per feature (four questions + out of scope)
├── plans/<slug>.md          ← plan + tasks
├── analysis/<slug>.md       ← analyze's cross-artifact report
├── progress/<slug>.md       ← append-only loop ledger + ## Decision queue
├── verifications/<slug>-YYYY-MM-DD.md
├── reviews/<slug>.md        ← closing review record
├── review-evals/<sha>.md    ← one case per revert that escaped review (`references/without-rsc-cli.md` §5)
├── archive/<slug>/
├── sessions/<date>-<slug>.md
└── decisions.md             ← append-only: every decision, and the task it was taken in
REVIEW.md                    ← project root: how this repo is judged
```

The workspace root is the folder that holds `02-DOCS/`; when none exists yet it is the project folder (tell the user once that it holds working notes they may want in `.gitignore`). Index every artifact in `02-DOCS/wiki/index.md` under the `sdd/` topic — never in the root `CLAUDE.md`.

## Stack handoff and skill registry

ASDD is process, not stack: `plan` defers stack specifics, `implement` borrows the stack's testing approach, `verify` runs its checks. The rsc stack skills (FastAPI, Next.js, Go, Postgres, Flutter, design) are not in this pack: where the text names one, use the project's own commands and conventions, and say so if a stack skill from elsewhere is loaded. There is no skill registry here; digest any stack skill you do use into 4-5 compact rules per subagent brief, and never load a whole catalog.

## Standard result envelope

Every phase ends with this block so the dispatcher can chain without interpreting prose:

```json result-envelope
{
  "status": "complete|blocked|failed",
  "executive_summary": "one short paragraph",
  "artifact": "path/to/artifact-or-none",
  "next_recommended": "constitution|specify|clarify|plan|tasks|analyze|implement|verify|review|ship",
  "risk": "low|medium|high",
  "skill_resolution": { "used": [], "missing": [], "fallback": [], "compact_rules": [] },
  "evidence": []
}
```

A run stopped mid-flight writes `02-DOCS/wiki/sdd/sessions/<date>-<slug>.md` instead: stage, artifacts, last verdict, done and parked tasks, the decision queue, next steps. Suggest the user keep the transcript beside it with `/export`, and `/compact` before the run resumes (`references/marcsh.md` §6). `/resume` reads this file and the progress file.

## Anti-patterns → STOP

| Rationalization | Reality / fix |
| --- | --- |
| "Tests are green, the feature is done." | Green proves it runs. Traceability to the spec proves it is what was asked; untraced behaviour is a finding. |
| "I'll review everything at the end." | That is how 40 correct tasks become a Frankenstein. Review inside each task, then once more at closing. |
| "This change is obviously low risk." | The tier is computed from the paths and the diff. The agent never picks or argues down its own tier. |
| "One more round and it converges." | Round 4 is refused. Rethink the approach or park the task. |
| "I'll wait for the user's answer." | Park the task in the decision queue and continue with independent work. |
| "The reviewer agent approved it, merge." | An agent's approval never counts as a human's. Tier 2 waits. |
| "The screenshots look alike." | Compare against a reference the human approved, or a deterministic diff. |
| "`asdd` should write the spec itself." | It dispatches. `specify` owns the spec. |
| "Ship with Co-Authored-By: Claude." | Authorship is the responsible person. No AI trailer, no generated-with footer. |

## Start here

- **New project** → `constitution`, then `specify`.
- **Existing project, new feature** → `specify` (proposal first if risky or architectural).
- **Small authorised change** → `../ftd/SKILL.md`.

Then follow the arrows: each phase ends by pointing at the next, all the way to `ship`.
