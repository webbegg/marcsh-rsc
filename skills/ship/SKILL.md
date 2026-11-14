---
name: ship
description: "Use when a verified branch that passed its closing review has to land — the close of rsc ASDD: safety checks, an explainer for the human (what changed, what the checks proved and would not catch), then three landing options (merge, PR with Testing/Risk/How to revert, park/discard). Risk tier 0-1 with CI green may self-merge; tier 2 waits for human approval. Authorship always the human, never an AI trailer. NOT running the gates (that is `verify`), NOT reading the diff for defects (that is `review`), NOT shipping to a server (rsc has a `deployment` skill for that; it is not in this pack)."
tags: [asdd, ship, release, pr, risk]
origin: risco
---

# Ship — close the development branch

Ship is the **last step** of ASDD's closing stage (`../asdd/SKILL.md`), after the closing review. Everything upstream proved the work is *correct* and *green*; ship is the act of **landing it** — turning an approved branch into merged history, a pull request, or a clean parked branch — without breaking the trunk and without ever forging the author.

This skill owns one decision and its safe execution: **how does this work integrate?** It does not write code, run test gates, or read the diff for defects — those phases already happened. It is the **close, not the open**: creating the isolated branch or worktree is a plain `git switch -c` or `git worktree add` (see `../plan/SKILL.md`, "Always propose isolation"), taking the gates green is `../verify/SKILL.md`, reading the diff adversarially is `../review/SKILL.md`, and putting merged code onto a server is outside this pack.

## The hard rule: git authorship is the responsible person, never an AI

> **Every commit and every PR ships under the name of the responsible person — the configured git user. No `Co-Authored-By: Claude`. No `Co-Authored-By` for any AI. No "🤖 Generated with Claude Code" footer. No "made by an agent" line in the PR body. Nothing that attributes the work to a tool.**

This is absolute — not a preference to weigh against convenience — because a commit is a permanent, published claim about who wrote something. The work is the responsible person's; the agent is a tool they used, like an editor or a compiler, and you do not credit the compiler in the commit message. Once a forged trailer is pushed it is in everyone's history and only a rewrite removes it.

Concretely, before any commit or PR:

- **Never** pass `--author` to set another author. The repo's configured `user.name` / `user.email` — the responsible person — is the author and committer.
- If `git config user.email` is unset or is an agent/bot identity, **stop and ask** which identity to commit under — do not guess, and do not substitute an agent identity.
- If you find a Claude/AI trailer in a commit you are about to push (e.g. left over from an upstream tool), **strip it** before the branch lands.

Verify it after writing the commit. A non-empty match is a blocker: amend and re-check before the branch goes anywhere.

```bash
git log -1 --format='%an <%ae>%n%n%b' | grep -iE 'co-authored-by.*(claude|anthropic|ai)|generated with|claude code' \
  && echo "AUTHORSHIP VIOLATION — strip the trailer before shipping" \
  || echo "authorship clean"
```

## Read these first

1. `02-DOCS/wiki/harness/user-profile.md`, if it exists — `technical_level`, the register. It sets the words only, never whether you run the safety checklist.
2. The **closing review verdict** for this branch — ship runs only on `APPROVE` or `APPROVE WITH NITS`. `CHANGES REQUESTED` loops back to `implement`, not forward to ship. If there is no verdict on record, say so and treat it as a red flag: do not ship a diff that skipped `../review/SKILL.md` — offer to run it first.
3. `02-DOCS/wiki/sdd/decisions.md` and the spec/plan slug — so the commit message and PR body describe *what shipped against which spec*, not a vague "various changes".

## The pre-ship safety checklist

Run this before presenting the landing options. Any unchecked item is a stop — surface it, don't ship around it.

- [ ] **Review verdict is APPROVE / APPROVE WITH NITS** (not CHANGES REQUESTED, not absent).
- [ ] **Working tree is clean** — `git status --short` is empty. No stray edits sneaking into the merge.
- [ ] **On a feature branch, not the trunk** — `git rev-parse --abbrev-ref HEAD` is not `main`/`master`. If work landed directly on the trunk, that is its own problem; flag it, don't paper over it.
- [ ] **Rebased / up to date with the base, and tested there** — branch is on top of latest `main`; conflicts resolved locally, not punted to the merge; the checks re-ran on the rebased branch.
- [ ] **Risk tier known** — computed for `git diff --name-only main...HEAD` by the table in `../asdd/references/without-rsc-cli.md` §1; its tier, classes and human-approval line go into the PR's Risk section.
- [ ] **No `blocking` entry in the decision queue** (`## Decision queue` in `progress/<slug>.md`) — or the PR says which remain and it does not self-merge. `review-after` entries never block; they are listed in the PR body (or the parked summary) for the human.
- [ ] **No secrets in the diff** — scan the staged/branch diff for keys, tokens, `.env` values (`git diff main... | grep -iE 'api[_-]?key|secret|password|token|BEGIN .*PRIVATE KEY'`). A hit is a blocker; remove it, and rotate it if it was ever pushed.
- [ ] **Authorship is the responsible person** — `git config user.email` is the configured human; no AI trailer in any commit on the branch (run the grep above across `main..HEAD`).
- [ ] **Commit history is intelligible** — squashed or organized so the history reads as deliberate, not "wip wip fix fix".

```bash
# one-shot pre-ship snapshot (read-only)
echo "branch:   $(git rev-parse --abbrev-ref HEAD)"
echo "clean?:   $([ -z "$(git status --short)" ] && echo yes || echo NO-dirty)"
echo "behind:   $(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?') commits behind origin/main"
git log main..HEAD --format='%an <%ae>' | sort -u   # authors on this branch — expect only the configured user
git diff main...HEAD | grep -icE 'api[_-]?key|secret|password|token|BEGIN .*PRIVATE KEY' \
  | sed 's/^/secret-hits: /'
git diff --name-only main...HEAD                    # the paths to score for the risk tier (see §1 of without-rsc-cli.md)
```

### The explainer — before the PR, for the human

Before any landing option, give the human a short explainer, in their register: **what the change
does** (behaviour, not files), **what the checks proved** (which tests, criteria, review tier), and
**what they would NOT catch** — the untested path, the environment only production has, the
judgement no test encodes. The last part is the point: it tells the human where to look. It also
goes into the PR's Testing section.

### No automated guard here — you hold the line

When rsc is installed for Claude Code, hooks enforce this phase: one denies any command that
switches to `main`/`master` or merges while the feature branch has uncommitted changes or unpushed
commits, and the sello denies commit, push and PR unless the change's exact bytes match a sealed,
approved review. marcsh runs no hooks, so **none of that exists here**. The same rules still
apply, by discipline: do not leave a feature branch with uncommitted or unpushed work, do not push
or open a PR on bytes that differ from the reviewed ones, and say plainly in the explainer that
nothing but you stood between this branch and the trunk.

## The three landing options — always present exactly three

This mirrors the "always 3 options" pattern. Gather the one fact that changes the answer (does this repo use PRs / require review on `main`?), then present **exactly three** with an honest recommendation matched to the workflow, in the user's register.

| Option | What it does | Choose it when |
| --- | --- | --- |
| **1. Direct merge to trunk** | Fast-forward or `--no-ff` merge into `main`, push, delete the branch | Solo repo or trusted-trunk workflow; `main` is not protected; you are the only reviewer and review already passed |
| **2. Pull request** | Push the branch, open a PR with a spec-linked body, let CI / a human gate the merge | `main` is protected; a team or CI must sign off; you want the change reviewable in the forge even if you self-merge |
| **3. Park or discard** | Keep the branch un-merged (park) or delete it (discard) | The approach was superseded, the spike answered its question, or the work is paused — it should not land |

**When the default branch is closed for the agent** (the project is complex or in production, has
CI or a team, or the user said branches and PRs; rsc keeps this as a per-project switch, here you
judge it from the signals below and ask if unsure), **option 1 is not offered**: a local merge is a
commit on the default branch. Present option 2 (the recommendation) and option 3, and say in one
line why option 1 is absent and that the user can ask for it explicitly.

Recommend based on repo signals: protected `main` or an existing PR culture (look for `.github/`, prior PRs via `gh pr list`) → recommend **option 2**. A solo project with no protection and a passed review → **option 1** is honest and faster. Never default to a PR ceremony the repo doesn't use, and never force-merge a repo that gates `main`. A tier-2 change takes option 1 only after human approval, same as a PR.

### Delivery strategy

Read the `Review Workload Forecast` in the plan, and `02-DOCS/wiki/sdd/config.yaml` if the user has one.

- `single-pr` keeps option 2 as one PR.
- `ask-on-risk` pauses when the forecast exceeds the review budget and asks before landing a large diff.
- `autochain` uses stacked PRs when tasks are reviewable in dependency order.
- `exception` permits a larger single PR only when the user explicitly accepts the review risk.

Stacked PR / feature-track support still fits inside the three landing options: it is a shape of **option 2**, not a fourth option. Use a feature-track branch when several stacked PRs should integrate together before trunk.

## Executing each option

**Nothing below runs before an option is picked.** Merging, pushing, opening a PR and deleting a branch are outward or irreversible — they change shared history or publish to a forge, and no later phase undoes them. Interactively, the user picks: a recommendation is not a yes; wait for one. (In YOLO approval mode the push and PR of option 2 need no chat yes, see the agent's Approval mode rule; merging and deleting still do.)

**In autopilot** (the user's up-front yes) the agent picks by these rules, and there is always a legal path:

- **A remote exists** → option 2, the PR. Self-merge only when the risk tier is 0-1, CI is green and **no `blocking` entry** is open; otherwise leave the PR open for the human. List every `review-after` entry in the PR body.
- **No remote** → option 3, **park**: leave the branch committed, write the explainer, the open queue entries and the exact merge command for the human (`git switch main && git merge --no-ff feature/<slug>`) into `progress/<slug>.md`, and stop.
- **Never merge locally into a default branch the project protects.** When the default branch is closed (see above), park instead of finding another command. Autopilot never discards.

### Option 1 — direct merge

```bash
git switch main && git pull --ff-only
git merge --no-ff feature/<slug> -m "feat: <what shipped> (<spec-slug>)"   # no AI trailer
git push origin main
git worktree remove ../<repo>-<slug> 2>/dev/null || true   # only if you made a worktree for it
git branch -d feature/<slug> 2>/dev/null || true
git push origin --delete feature/<slug> 2>/dev/null || true
```

Use `--no-ff` so the feature is one legible merge commit tied to the spec. Confirm the trunk still builds after the merge if the repo has a local gate (defer the actual run to `verify`).

**Cleanup is yours to run here.** rsc retires a landed worktree and its branch with a `post-merge` hook; marcsh has no hooks, so after the work lands you do it, in the same turn, and check that it happened (`git worktree list`, `git branch --merged`). Remove only a worktree and branch that you created or that the user named, and only once the work is in the trunk. Anything holding unsaved work (`git status` in the worktree) stays, with the reason said. Name the path when you remove a worktree: with two streams running, removing by guess is how shipping A deletes B.

### Option 2 — pull request

Write the **commit(s)** clean, push, then open the PR with `gh`. The PR body links the spec/plan and lists what shipped — **and carries no AI attribution.**

```bash
git push -u origin feature/<slug>
gh pr create \
  --title "feat: <what shipped> (<spec-slug>)" \
  --body-file /tmp/ship-pr-body.md          # body authored per the template below — NO AI footer
```

PR body shape (no generated-with line, ever):

```markdown
## What

<one-paragraph summary of the change, in plain terms>

## Why

Implements `02-DOCS/wiki/sdd/specs/<slug>.md`. <the user-facing reason>

## Testing

- <what ran: lint / types / tests / verify record; acceptance criteria met, each with its evidence>
- Closing review: APPROVE (<N> findings, all with an outcome).
- Not covered: <what these checks would NOT catch — from the explainer>

## Risk

Tier <0|1|2>: <classes touched>. Human approval: <required|not required>.
Decision queue: <open `blocking` entries, or none> · Review after: <each `review-after` entry, or none>.

## How to revert

<`git revert <merge-sha>` / the squash commit; plus anything a revert alone does not undo — a migration, a flag, data written>
```

**Merge policy — by risk tier.** Tier 0-1, CI green and no `blocking` entry in the decision queue
→ you may self-merge (autopilot): `gh pr merge --squash --delete-branch` (or `--merge` to preserve the
history; squash when the branch history is noisy, preserve when each commit is meaningful). **Tier
2 waits for human approval** — a human's approving review on the PR, or their explicit yes in the
conversation. An agent's approval never counts as a human's: no refuter, reviewer subagent or bot
review stands in for it, however clean.

Once it is merged, pull the trunk — `git switch main && git pull --ff-only` — then clean up as above. A squashed pull request does not show as merged to git (`git branch --merged` will not list it), so check the PR state instead; keep the local branch until the user agrees to delete it, because `git branch -D` is not recoverable and while the branch exists the work is.

For stacked PRs, create each PR against the previous branch or against a feature-track branch, with bodies that name their dependency:

```markdown
Depends on: <previous PR or feature-track branch>
Part of: <spec-slug>
```

Never stack to hide review risk. Stack because each slice is independently reviewable and follows the task dependency order.

### Option 3 — park or discard

- **Park:** leave the branch committed, push it if a remote exists (`git push -u origin feature/<slug>`), and log *why it's parked* to `02-DOCS/wiki/sdd/decisions.md`. Do not merge. A branch parked *ready to land* (autopilot, no remote) also gets its explainer, open queue entries and the exact merge command in `progress/<slug>.md`, so the human lands it with one command.
- **Discard:** deletion is **destructive and unrecoverable** once the branch is gone from both sides, so it takes an explicit confirmation that quotes the branch name (the literal `yes, delete feature/<slug>`) before `git branch -D`. Anything ambiguous means keep it. Log the discard and the reason so the dead-end is remembered, not re-attempted.

**Park and discard do NOT clean up.** Cleanup acts only on work that is already in the trunk; a
parked branch is the opposite of that. Leave the worktree where it is — the next `ship` that lands
the branch will retire it. Discarding a worktree along with unmerged work is explicit, confirmed
with the quoted branch name, and logged.

If a native worktree tool of the engine created the workspace, exit through that tool — it owns its
own lifecycle.

## Commit message discipline

The commit is the durable record. Make it describe the change and tie it to the spec — and keep it the responsible person's.

- **Subject:** follow the project's convention (read `git log --oneline -20` first). Where it has none, use `type: imperative summary (<spec-slug>)` — `feat:`, `fix:`, `refactor:`, etc. — under ~72 chars. rsc's own convention adds a gitmoji (`✨ feat:`, `🐛 fix:`); use it only if the project does.
- **Body:** *why*, not a restatement of the diff. Reference the spec slug and any decision logged in `decisions.md`.
- **Footer:** issue/PR refs only. **No `Co-Authored-By` for any AI. No "generated with" line.** This is where the violation usually sneaks in — leave the footer clean.

## What ship shows

Read `technical_level` from `02-DOCS/wiki/harness/user-profile.md` if the file exists. It changes the words, **never** the safety checklist or the authorship rule. No profile → use analogies and proceed; don't stall the ship to ask.

In short plain sentences: the explainer, the checklist result in one line, the three options as one-liners, the recommendation and its *why*, then execute on a yes (in YOLO approval mode, a push or PR needs none) — e.g. `Clean, rebased, authorship <git user>. Recommend PR (main is protected). Open it?`. For a `non-technical` owner, explain the recommended option with an analogy: a protected `main` wants a PR ("asking permission before changing the shared copy"). Explain fast-forward vs `--no-ff` or what squashing trades away only when asked.

## Anti-patterns → STOP

| Rationalization | Reality |
| --- | --- |
| "I'll add `Co-Authored-By: Claude` / a 'Generated with Claude Code' footer to be transparent" | It forges the record. The work is the responsible person's — no AI trailer, ever. Strip it. |
| "Review didn't formally approve but it's obviously fine" | No verdict = not ready. Ship runs on APPROVE only. Route back to review. |
| "Tier 2, but the three lenses approved — I'll self-merge" | An agent's approval never counts as a human's. Tier 2 waits for human approval. |
| "Tier 2, one reviewer was enough here" | rsc's push gate wants the panel recorded; here you hold that line. Run the three lenses, record the panel line in the progress file, then push. |
| "The tree has a couple of stray edits, they're harmless" | A dirty tree means the merge is not the reviewed diff. Clean it or stash it first. |
| "`main` is protected but I'll just force-merge, I'm sure" | Protected means PR. Don't bypass the gate the repo deliberately set. |
| "No remote and the guard denies the merge — I'll merge another way" | The denial is the answer. Park the branch with the merge command for the human. |
| "I'll rebase and resolve conflicts during the merge" | Resolve before. A conflicted merge commit hides what actually shipped. |
| "This branch is dead, I'll just delete it" | Discard is destructive — confirm with the quoted branch name and log why first. |
| "Squash everything, history doesn't matter" | Squash noise, preserve meaning. The history is the next reader's spec. |
| "There's a key in the diff but it's a test key" | A secret in the diff is a blocker regardless. Pull it out before landing. |

## Where this writes

Ship is mostly git actions, but the outcome is recorded so the knowledge model stays whole:

- **The landing decision** (which of the three options, and why) → append to `02-DOCS/wiki/sdd/decisions.md`, the same append-only log `implement`, `verify`, and `review` write to. Parks and discards are logged with their reason so dead-ends aren't re-walked.
- A **shipped feature** flips its spec under `02-DOCS/wiki/sdd/specs/<slug>.md` to a shipped state (note the merge commit / PR). Ship keeps the `sdd/` rows in `02-DOCS/wiki/index.md` (the Knowledge map) honest — never the root `CLAUDE.md`.
- An **archive bundle** closes the loop under `02-DOCS/wiki/sdd/archive/<slug>/`:
  - `final-report.md` — what shipped, why, landing decision, links.
  - `apply-progress.md` — copy or link to `progress/<slug>.md`.
  - `verification.md` — copy or link to the verification record.
  - `review.md` — review verdict and nits.
  - `state.yaml` — `shipped`, `parked` or `discarded`, PR/merge refs, date.

Archive after option 1/2 lands, and also after option 3 parks/discards so paused or abandoned work is remembered.

## Result envelope

End with:

```json result-envelope
{
  "status": "complete",
  "executive_summary": "Branch landed/parked/discarded and SDD archive updated.",
  "artifact": "02-DOCS/wiki/sdd/archive/<slug>/final-report.md",
  "next_recommended": "none",
  "risk": "low|medium|high",
  "skill_resolution": {
    "used": ["ship"],
    "missing": [],
    "fallback": [],
    "compact_rules": ["Keep exactly three landing options.", "Archive the final state."]
  },
  "evidence": ["closing review verdict", "risk tier and reason", "verification record", "PR/merge/park/discard reference", "human approval when tier 2"]
}
```

## Next in the chain

Ship is the end of the ASDD loop for a feature. Two onward paths: the merged code still has to reach a **server / release** → that is outside this pack (the project's own deploy process); or the next feature restarts the loop at **specify** (`../specify/SKILL.md`), or at **constitution** if the project's principles changed. The `asdd` dispatcher (`../asdd/SKILL.md`) routes whichever comes next. Later, a revert of what shipped is an escape: `review` turns it into a case (`../asdd/references/without-rsc-cli.md` §5).
