---
name: suggest
description: "The lane decisor, trimmed for marcsh. Use at the start of every turn to classify it before anything is written: answer (read-only, information only), FTD (ordinary authorised change, one feature document) or ASDD (big work, or decisions that affect each other, spec first). Triggers on any request in any language. NOT the skill installer of the rsc harness: that part is removed."
tags: [suggest, decisor, lanes]
origin: risco
---

# suggest — the decisor: classify the turn before acting

Adapted from rsc's always-on `suggest` skill. Only its first job is kept: **classify every turn into
one of three lanes before anything is written.** The rest of the original (offering to install
missing skills with `npx @ericrisco/rsc add`, repairing a broken harness, first-contact onboarding,
the «recuerda esto» memory rule) belongs to the rsc installer and is not part of this pack.

Every turn takes one of three lanes, and you name the one you took in a line, in the person's
language (the lane names are labels to translate).

**Answer** — the request asks for information: explain, compare, investigate, audit, review,
recommend. Read-only: write nothing, create no artifact, delegate no writer. Asking you to *think
about* building something is still this lane; only asking to build authorises it. When change
intent is ambiguous, ask one question and stay here — ambiguity slows the lane, never raises it.
Ask it with the question tool (`../asdd/references/marcsh.md` §3): "Just the answer" and "Make
the change". It asks whether to change anything, never which lane.

**You choose the lane; never hand that choice to the person.** Simple → **FTD**: one feature document
in `02-DOCS` (intent, scope, checklist, evidence, next step), tasks checked off against observed proof.
Big, or decisions that affect each other → **ASDD**: enter the chain; the person approves the spec and
clarify, then picks manual or autopilot. Say which and why in one line; switch if asked.
→ `../ftd/SKILL.md` · `../asdd/SKILL.md`.

**Where.** marcsh blocks every commit on the default branch. On it, before the first code change,
ask with the question tool: a new branch (recommended) or a worktree. On another branch, an
unrelated change asks first: this branch or a new one. Never branch alone. Another session in this
folder → a separate worktree. Details: `../asdd/references/without-rsc-cli.md` §6.

Judge the **meaning**, not the wording: the trigger is semantic in any language. A bug fix restoring
intended behaviour is `debug`. Autopilot consent covers a whole run — advance without re-asking.

**Which agent is running.** The pack has two agents, and both load these same skills, so either can
run any lane. The FTD agent starts from Answer and FTD, and enters ASDD by following
`../asdd/SKILL.md` when the decisor says so. The ASDD agent starts as the chain's dispatcher; for a
small authorised change it says so and offers to do it as FTD. An agent cannot switch itself; the
user switches with Tab or `/agents`, and the long autonomous run is the ASDD agent's job.

## Explain without assuming

Define a term at first use; never give a command, flag or path without saying what it does.
