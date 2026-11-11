---
name: review
description: "Use when a diff needs adversarial judgment in rsc ASDD — per task inside implement's loop (depth set by the risk tier: none, one fresh-context reviewer, or the three-lens panel) or as the closing review of the whole branch against the spec — keyed to the spec/plan/constitution in 02-DOCS/wiki/sdd/ and the project's REVIEW.md; or receive a review and verify each comment before agreeing. Converges via a review ledger (max 3 rounds, no repeated finding). NOT running lint/type/tests (that is `verify`), NOT merging (that is `ship`)."
tags: [asdd, review, code-review, risk]
origin: risco
---

# Review — adversarial code review, both directions

Tests prove the code works, not that it does what was asked. Review answers that other question: **is the diff correct, well-scoped and faithful to the spec — or did it pass for the wrong reasons?** In ASDD (`../asdd/SKILL.md`) it runs in two modes:

- **Per task** — called from `implement`'s loop after each task's self-check. Depth comes from the risk tier, computed by hand from the path table and content signals in `../asdd/references/without-rsc-cli.md` §1: **tier 0** → no review; **tier 1** → one fresh-context reviewer (a subagent that never saw the implementation conversation); **tier 2** → the three-refuter panel below, recorded after it runs as a panel line in the progress file (`<task>: panel correctness, security, tests`; rsc's ship guard refuses to push a tier-2 branch without it, marcsh has no guard so you hold that line — one reviewer is not a panel), and the branch will wait for human approval at ship. The tier reads the diff's content too: auth code in a generic file is tier 2.
- **Closing review** — once, before `ship`: the whole branch against the spec. Forty individually-correct tasks can still fail to be the feature together: a criterion nobody owned, two tasks that each assumed the other handled an edge, scope that crept in a slice at a time. Read the spec's acceptance criteria and "must respect" list against `git diff <base>...HEAD`, not the task reviews. Its record — tier, counts, verdict, each finding with its outcome — goes to `02-DOCS/wiki/sdd/reviews/<slug>.md`.

This skill owns **two roles that share one discipline**:

- **Giving** a review — read a diff adversarially, find the real defects, rank them by impact, ship the verdict as evidence not opinion.
- **Receiving** a review — take incoming feedback (human or machine), verify each point against the code *before* acting, fix the real findings, and push back — with proof — on the wrong ones.

The discipline is the same in both directions: **every finding and every rebuttal carries evidence — no agreement without verification, no objection without a defect.** A reviewer who waves through a bug to be agreeable, and an author who edits working code because a comment *sounded* authoritative, are making the same mistake. Everything below is in service of that one rule.

**Route out** when the ask isn't this gate: a deep OWASP / threat-model pass is its own piece of work (rsc has a `security-audit` skill for it; it is not in this pack, so say so and scope the security lens to the diff); a "is this idiomatic React/FastAPI/Go/SQL" question belongs to the stack's own conventions or a stack skill if one is loaded — pull the idiom there, then judge against it here.

## Read these first

1. `REVIEW.md` at the project root, if present (drafted by `constitution`): what failure looks like in this repo, paths to skip, the nit cap, and that the summary starts with a count ("3 findings: 1 blocker, 2 nits"). Where it differs from this skill's defaults, it wins.
2. `02-DOCS/wiki/sdd/specs/<slug>.md` and `02-DOCS/wiki/sdd/plans/<slug>.md` — what the diff was *supposed* to do. A review with no spec is a review of vibes.
3. `02-DOCS/wiki/sdd/constitution.md` — the project's non-negotiables (stack canon, quality bars, conventions). Constitution violations are findings even when the code "works".
4. `02-DOCS/wiki/harness/user-profile.md`, if it exists — `technical_level`, the register (see "How a review reads" below).

If there is no spec/plan (someone jumped straight to code), say so and review against the constitution + the diff's own stated intent. Don't pretend a spec exists.

## Confidence filtering

A review's value is its signal-to-noise. Every finding you report costs the author triage time, so report only what you can stand behind:

- **>80% sure, or it doesn't ship.** If you're not >80% confident a finding is a real defect, either trace it until you are, or downgrade it to `[question]` and ask. Plausible-looking ≠ verified.
- **Zero findings is an acceptable verdict.** A clean diff gets `APPROVE`, not a manufactured nit. Padding a report to look thorough is the opposite of thorough.
- **Common false positives to skip:** patterns guarded two functions up; "unsafe" calls on values that are provably constant/internal; missing checks the framework already enforces; style the linter owns; defects behind a flag that's off everywhere (note as `nit`, not blocker); test-only or generated code held to prod standards.
- **No severity inflation.** A `should-fix` dressed as a `blocker` burns the same trust as a missed bug. Rank by actual blast radius and reachability — if everything is a blocker, nothing is.

This skill is the discipline. In rsc a separate review bundle (`/code-review`, `/security-audit`) executes it with a reviewer fleet; that bundle is not in this pack, so the discipline is run by you, and by fresh-context subagents where the engine has them.

---

## GIVING a review

A good review is not a list of everything you'd have done differently. It is a ranked set of **defects that matter**, each one reproducible from the diff itself.

### The pass order

Run these passes in order; each is cheap and catches a different class of defect. Stop padding the report once a pass is clean — a clean pass is a finding too ("auth path: checked ownership scoping, correct").

| Pass | The question | Typical defects |
| --- | --- | --- |
| **1. Spec fidelity** | Does the diff do what the spec/plan said — no more, no less? | Missing acceptance criteria; scope creep; a TODO masquerading as done |
| **2. Correctness** | Is it right on the boundaries, not just the happy path? | Off-by-one, null/empty/zero, error paths swallowed, race, wrong operator |
| **3. Contracts & data** | Do the interfaces and data shapes hold? | Breaking API change, nullable mismatch, migration that loses data, N+1 |
| **4. Security boundary** | Any untrusted input reaching a sink? | Injection, authz gap (authenticated ≠ authorized), secret in diff, SSRF |
| **5. Tests as evidence** | Do the tests actually exercise the change, or just pass? | Asserts on mocks, no failing case, happy-path-only, deleted assertions |
| **6. Constitution & fit** | Does it honor the project's canon and read like the codebase? | Banned pattern, wrong layer, duplicated logic, dead code left behind |

Passes 1–5 are correctness/safety — those produce **blocking** findings. Pass 6 is fit — usually **non-blocking** unless it violates a stated constitution rule.

### Severity — rank or it's noise

Tag every finding. An unranked review forces the author to triage your opinions; a ranked one tells them exactly what blocks the merge.

- **`blocker`** — ships a bug, a vuln, data loss, or breaks the spec. Merge does not happen until resolved.
- **`should-fix`** — real defect, narrow blast radius; fix now or file a tracked follow-up the author agrees to.
- **`nit`** — style/preference with no correctness impact. Explicitly labelled, never blocking, the author may decline freely.

If everything is a blocker, nothing is. If everything is a nit, you didn't review.

### Finding format

Each finding is a quoted location, the defect, the evidence, and a concrete fix. No "consider maybe looking at error handling here."

```text
[blocker] auth: authenticated user can read any document
  where:  api/documents.py:42  return db.get(Document, doc_id)
  why:    doc_id comes from the path; no owner check. Any logged-in
          user enumerates every document by id.
  repro:  GET /documents/<other_users_id> with a valid session → 200 + body.
  fix:    scope the query — WHERE id == doc_id AND owner_id == current_user.id;
          return 404 (not 403) on miss to avoid leaking existence.
```

A finding without a `repro` or a mechanism is a *suspicion*. Label it `[question]` and ask, don't assert it as a defect.

### Verify before you flag

The reviewer is held to the same evidence bar as the author, because a reviewer who cries blocker on a non-bug burns the same trust as an author who ships one. Before writing a `blocker`:

- **Read the surrounding code**, not just the diff hunk. The check you think is missing may live two functions up.
- **Trace the value**, don't pattern-match. "This looks like SQL injection" is not a finding; "this f-string interpolates `request.args['q']` straight into `execute()`" is.
- **Confirm the path is reachable.** A defect behind a flag that's off in every environment is a `nit`, not a `blocker` — say so.

### The verdict

End every review you give with one of three, and nothing mushy in between:

- **`APPROVE`** — no blockers, no unresolved should-fix. Say it plainly and **point to ship**.
- **`APPROVE WITH NITS`** — mergeable; the nits are the author's call.
- **`CHANGES REQUESTED`** — one or more blockers/should-fix. List exactly what unblocks it.

### The sello — not available here

rsc can seal a review verdict to the exact bytes reviewed (`sello freeze`, `approve`, `block`,
`budget`) and have a hook refuse commit, push or PR on anything else. That needs rsc's install and
hooks, so it does not exist under marcsh. Do not run those commands and do not claim a verdict is
sealed. What is left is the discipline: **name the exact state you reviewed** (commit SHA, or the
diff range) in the review record, and re-review the divergence if the code changes after the
verdict. The user owns the delivery step; at tier 2 nothing ships without their yes.

### Depth by risk — who reviews

The tier comes from the path table (`../asdd/references/without-rsc-cli.md` §1). Tier 0 never
reaches you (docs/copy pass silently); tier 1 → **one fresh-context reviewer** running the most
relevant pass from the table above; tier 2 → **three parallel fresh-context subagents**, one per
lens (**correctness**, **security**, **tests**), each told to *refute* readiness, not confirm it.
Fresh context is the point: a reviewer who inherits the implementer's context inherits its blind
spots. The closing review is always at least tier 1.

rsc ships named agents for these roles (`refuter-correctness`, `refuter-security`,
`refuter-tests`, `finding-verifier`); this pack does not. Write each dispatch from this skill's text.
If your engine cannot start subagents, run the lenses one after another yourself, each from the
four inputs below only, and record in the review that the context was not independent. At tier 2
that is a weaker check, and the user decides whether it is enough.

**Give each refuter exactly four inputs — no more, no less.** The diff alone is not enough, and
that is not a detail: with only the diff, the one failure class no test suite can structurally
catch — *the change is correct and is not what the approved spec asked for* — is invisible to the
whole panel.

1. **The task contract** — the original request **plus every scope change a human explicitly
   approved since.** Not just the first message: without the approved changes a legitimate scope
   revision reads as a spec gap and you get a confident false positive.
2. **The approved spec** (`02-DOCS/wiki/sdd/specs/<slug>.md`).
3. **The exact source state** — commit SHA, or a tree hash when git is absent. A verdict belongs to
   the state that was reviewed, not to the project.
4. **The entry point** — the one command that reruns the checks.

**And say what they do not get:** your conversation, your reasoning, your defences, and your draft
verdict. If a claim needs your justification to stand, it is not proven.

**Blind first, compare second.** Each refuter records what it attacked and what it found *before*
being shown your conclusions. Only then may it compare and add findings — the blind record is
append-only after that, never rewritten. Skip this and the fresh context is spent confirming your
framing, which is the one thing it was bought to avoid.

**The attack list is the deliverable, not just the findings.** "Nothing found" without saying where
you looked is indistinguishable from not having looked — the same rule that governs a dismissal.

Two extra finding classes the four inputs unlock, neither reachable from a diff:

- **Contract vs spec** — what would a caller reasonably expect, given the stated deployment, that
  no clause covers? An exclusion the spec deliberately approved is **not** a finding; an exclusion
  the spec describes *inaccurately* is.
- **Mapping, both directions** — an acceptance criterion with no test that can be made to fail, and
  a test pinning behaviour no criterion asked for.

**Consolidate, then verify — before anything reaches the author.** Three lenses on one diff often
report one defect three ways, and a lens hunting for something can overstate what it found. Two
steps, in this order:

1. **Group (deterministic).** Each lens ends its report with a ` ```json findings ` block — an
   array of objects in exactly this shape (give it to every reviewer verbatim):

   ```json
   {"severity":"blocker|should-fix|nit|question","file":"path","line":N,"claim":"…","failure_scenario":"concrete input → wrong result","evidence":"quoted code","class":"bug class"}
   ```

   Merge the reports by hand (`../asdd/references/without-rsc-cli.md` §4; rsc's `review
   consolidate` does the same mechanically). Findings on the same place that say the same thing, or
   that quote the same evidence, become one; keep the highest severity and every lens that saw it;
   and **downgrade a blocker or should-fix with no `file:line` or no `failure_scenario` to a
   question**. Several lenses on one finding is a reason to look first, never a reason to raise its
   severity.
2. **Verify (judgement).** **Every blocker and every should-fix** is verified. For each, start a
   fresh verifier (a subagent if the engine has them, else a separate pass) with that one finding
   plus the same four inputs, in parallel where possible. It starts from "this is false" and
   returns **CONFIRMED** (reproduced or traced, with the proof), **REFUTED** (cites the guard that
   makes it impossible), or **UNPROVEN** (becomes a question). It never gets the lens's reasoning.

Report the consolidated count honestly ("11 reported → 4 unique → 2 confirmed"), and list what was
refuted and why: a refuted finding hidden from the author is a review nobody can audit. At tier 1
(one reviewer) there is nothing to group, but apply the downgrade rule to its one report anyway,
and every blocker and should-fix is still verified.

**A finding blocks only if it survives all three filters** — no exceptions, and eagerness to
find something is not evidence:

1. **Causal** — introduced by *this* change. Pre-existing defects → list them under a
   `Not blocking` heading in the review record and suggest an issue; they never block this
   delivery.
2. **Severity** — only `blocker` blocks. `should-fix`/`nit` → listed under `Not blocking`.
3. **Evidence** — the verifier returned **CONFIRMED** with its proof. REFUTED is dropped (with
   its reason in the report); UNPROVEN is a `[question]`, and questions don't block.

**Fixing a blocker is budgeted.** Before touching anything: estimate the fix in changed lines and
write it in the progress file. After the fix: compare (`git diff --shortstat`); over budget →
justify in one line or shrink the fix; an unexplained overrun is how over-engineering enters
disguised as a fix. Then re-review **only the divergence**, and approve. Each fix-and-re-review is
one round of the loop below.

### Convergence — the fix loop ends

A review loop that never converges is worse than none: Anthropic saw a single PR take 50 rounds.
Four rules, kept in a written ledger rather than in memory (rsc's `review ledger` command does this
mechanically; here the ledger is a `## Review rounds` list in the progress file,
`../asdd/references/without-rsc-cli.md` §3):

1. **Max 3 rounds per task.** Append the round line (`<task>: round N`) before **every** review of
   the task, the first included: round 1 is the task's first review, not its first fix. The 4th is
   refused. That is not "try harder": rethink the approach, or park the task in the decision queue
   (a `blocking` entry) and continue with independent work.
2. **From round 2, re-review only the new diff** — what changed since the last round, not the task
   again from scratch.
3. **Flag the bug class, not the line.** "Every handler in this file trusts `req.params.id`" — so
   one fix covers every instance and round 3 does not find the sibling.
4. **Never repeat a finding.** Record each round's findings in the ledger. A finding already seen —
   same file, class and meaning — is marked `repeat`; it is never re-raised as new. A repeat means the
   last fix missed the class, so say that instead.

**Every finding closes with an outcome**: `fixed|false|intentional|irrelevant|parked` — `parked`
when the finding's task went to the decision queue (neither fixed nor dismissed; a human decides).
Counting the outcomes gives the false rate and the mean rounds per task — the only way to tell
whether a change to the reviewer made it better or worse.

The ledger lives in the progress file, under `02-DOCS`. What lasts beyond it is what you write from
it — review-evals cases and rules (below).

---

## RECEIVING a review

This is the half everyone skips. Feedback arrives and the reflex is to either comply with all of it (looks cooperative, ships bugs) or dismiss the annoying parts (looks confident, ships bugs). Both skip the only step that matters: **checking whether the finding is true.**

### Process every comment through this gate

For each incoming finding, before touching a line of code:

```text
1. RESTATE   — what is the reviewer actually claiming is wrong? (in one sentence)
2. VERIFY    — go to the code. Is the claim true? Trace it. Can you reproduce it?
3. CLASSIFY  — true defect / partially-true / false / unclear
4. ACT       —
     true        → fix it, and add the test that would have caught it
     partial     → fix the real part, reply on the rest with evidence
     false       → DON'T change the code. Reply with the proof it's already handled
     unclear     → ask one specific question; don't guess and don't pre-emptively edit
```

The expensive failure is step 2 skipped. Editing working code because a comment *sounded* right introduces bugs the original author (you) already prevented.

### Pushback is a feature, not rudeness

Disagreeing with a wrong finding — **with evidence** — is doing the job, not being difficult. The reply is not "you're wrong"; it's the trace:

```text
> Reviewer: this can NPE if `user` is null.
Verified: `user` is non-null here — it's the return of `require_auth()` on
line 12, which raises 401 before this line on a null session. Added a test
(test_get_doc_unauthenticated) that asserts the 401 so this stays true.
Leaving the code as-is.
```

That reply *strengthens* the diff (it added a regression test) while declining the change. That's the bar.

### Performative agreement is the failure mode

The tells, and what to do instead:

| Tell | Reality | Do instead |
| --- | --- | --- |
| "Good catch!" then editing without checking | You don't yet know if it's a catch | Verify first; *then* "good catch" or "checked — already handled" |
| Rewriting a whole function to satisfy a nit | Scope creep dressed as responsiveness | Make the minimal change the nit asks for, or decline it as a nit |
| Silently making the change the bot suggested | Bots flag plausible-looking non-bugs constantly | Trace it like any other finding; reply with the verdict |
| "You're probably right" with no trace | Probably-right is not verified | There is no probably. Reproduce it or refute it |

### Author's verdict

When you've processed the review, summarize for the reviewer (and the decisions log): findings accepted + fixed (with the commit/test), findings declined + why (with evidence), findings deferred + tracked. Then the diff is ready to re-review or, if clean, to ship.

---

## Anti-patterns → STOP

| Rationalization | Reality |
| --- | --- |
| "It passed verify, so it's correct" | Green gates prove it runs and tests pass, not that the logic is right. Review is the logic gate. |
| "I'll list everything I'd do differently" | A review is ranked defects, not your preferences. Tag nits as nits or drop them. |
| "This pattern usually means a bug" | Usually isn't a finding. Trace this instance or label it `[question]`. |
| "The reviewer is senior, they're probably right" | Seniority isn't evidence. Verify the claim against the code like any other. |
| "Just apply all the comments, it's faster" | Applying a false finding ships a regression. Each comment goes through the gate. |
| "Pushing back will look defensive" | Pushing back *with a trace* strengthens the diff. Silent compliance hides bugs. |
| "I'll approve it, the issues are minor" | If they're truly minor, label them nits and approve. If they block, don't approve. No mushy middle. |
| "No spec, so I'll just eyeball it" | Say there's no spec and review against the constitution + stated intent. Don't fake a baseline. |

## How a review reads

Read `technical_level` from `02-DOCS/wiki/harness/user-profile.md` if the file exists. It changes the words, never the rigor — every reader gets the same passes and the same evidence bar. No profile → use analogies and proceed; don't stall a review to ask.

In short plain sentences: the verdict first, then the blocker list — e.g. `CHANGES REQUESTED: 1 blocker (auth, documents.py:42), 1 nit. Fix the auth scope and re-run verify.` Each finding keeps its full format (where/why/repro/fix) and names its defect class (IDOR, N+1, TOCTOU). For a `non-technical` author, translate the impact ("any logged-in person could read everyone else's documents").

## Where this writes — and how the reviewer learns

- **Accepted/declined findings** of consequence → append to `02-DOCS/wiki/sdd/decisions.md` (e.g. "declined NPE finding on documents.py:42 — guarded by require_auth; added regression test"). This is the same append-only log `implement` writes to.
- **Escapes become cases.** List the revert commits (`git log -i --grep='^revert' --oneline`, `../asdd/references/without-rsc-cli.md` §5) and check whether each has a case at `02-DOCS/wiki/sdd/review-evals/<shortsha>.md`. Write the missing ones: the diff that shipped, where the bug was, and what the reviewer should have said. Only `Revert "…"` / `revert:` commits are seen; a hand-made revert is invisible.
- **A finding that keeps repeating becomes a rule** — a lint rule, a constitution principle (`02-DOCS/wiki/sdd/constitution.md`, amended via `constitution`) or a line in `REVIEW.md`. Ask what the model didn't have in front of it: a repeat is almost always missing context, not a careless reviewer.

Index them in `02-DOCS/wiki/index.md` (the Knowledge map; root `CLAUDE.md` keeps only a short pointer) under the `sdd/` topic; this skill keeps its rows honest.

## Result envelope

End with the parseable block every phase shares, so the dispatcher can chain without
interpreting prose (contract: `../asdd/SKILL.md`):

```json result-envelope
{
  "status": "complete|blocked|failed",
  "executive_summary": "Per-task or closing review against spec/plan/constitution/REVIEW.md; tier, round, verdict and blocking findings.",
  "artifact": "02-DOCS/wiki/sdd/reviews/<slug>.md",
  "next_recommended": "ship",
  "risk": "low|medium|high",
  "skill_resolution": {
    "used": ["review"],
    "missing": [],
    "fallback": [],
    "compact_rules": ["Rank or it is noise: blocker / should-fix / nit.", "A finding without a repro is a question, not a defect.", "Max 3 rounds; never repeat a finding."]
  },
  "evidence": ["risk tier and reason", "verdict stated (APPROVE | APPROVE WITH NITS | CHANGES REQUESTED)", "each blocker carries location + repro + fix", "every finding has a ledger outcome"]
}
```

## Next in the chain

Per task: **APPROVE** returns to `implement`'s loop for the next task; **CHANGES REQUESTED** goes back to the fix step of the same task, as the next round. Closing review: **APPROVE** / **APPROVE WITH NITS** with every blocker resolved hands off to **ship**, with **git authorship as the human, never an AI**; anything else goes back to `implement`. Don't ship a diff that hasn't earned its verdict.
