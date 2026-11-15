# marcsh-rsc

Two workflows for marcsh, packaged as an agent pack:

- **FTD** (Fast-Track Development): the lane for ordinary changes. One short feature document, tasks checked off only against observed proof, a minimal risk loop.
- **ASDD** (Agent Spec-Driven Development): the lane for big work. A spec the user approves, a plan, tasks, a per-task build and review loop scaled by risk, a decision queue, and a closing review.

Both come from [rsc-harness](https://github.com/ericrisco/rsc-harness) by Eric Risco (MIT) and are adapted to run under marcsh, without the `rsc` command line tool: named reviewer subagents, entry-point commands, background work for long commands, multiple-choice questions at every gate, and optional hooks for the hard gates. See [Credit](#credit) and [Limits](#limits).

Requires marcsh 0.4.0 or later for named subagents and agent-aware commands; on 0.3.x subagent briefs are passed inline and commands run as the selected agent.

## Install

```text
/agents install webbegg/marcsh-rsc
```

marcsh shows what the pack contains and asks before it enables anything. Updates are explicit: `/agents update webbegg/marcsh-rsc`.

Then pick **FTD** or **ASDD** with Tab or `/agents`, or start a turn with one of the pack's [commands](#commands), which runs as the agent it names. The pack's skills load only for a turn that runs as one of its two agents.

The pack's hooks are off after the install. To turn them on, run `/agents hooks webbegg/marcsh-rsc`, scroll the review to the end and choose **Enable**; `/agents hooks webbegg/marcsh-rsc off` turns them off (see marcsh's pack hooks documentation). They are pinned to the commit you reviewed; an update turns them off until you review again.

## What each agent does

**FTD** (`agents/ftd.md`) is an always-on operating prompt. Every turn it first chooses a lane and says which: *answer* (read-only, nothing written), *FTD*, or *escalate to ASDD*. For FTD it writes a feature document at `02-DOCS/wiki/ftd/<slug>.md` before the first change (intent, scope, checklist, evidence, next step), checks tasks off only against observed output, computes the risk tier of the change, asks for one fresh-context review from tier 1, and asks where the work should run before it writes code on a branch that looks protected. It escalates to ASDD at tier 2 or when a change contradicts a recorded decision.

**ASDD** (`agents/asdd.md`) is the dispatcher of the chain: constitution, specify, clarify, plan, tasks, analyze, implement (verify and review inside every task), closing, ship. Artifacts go under `02-DOCS/wiki/sdd/`. The user approves the spec, answers the decision queue, and approves a tier-2 merge; everything else runs. It supports an up-front "take it all the way" (autopilot) that parks questions in the queue instead of stopping.

Neither agent sets a `model`: the session model is used.

Both agents use marcsh's own features where the method needs them (`skills/asdd/references/marcsh.md`):

- **Long commands in the background.** Focused tests run in the foreground; full suites, builds, audits, `git bisect run`, `gh pr checks --watch` and dev servers go to `bg_start` on pi (the engine's background mode on Claude) or get an explicit `timeout`, so the 3-minute limit never turns a check into a false result. The rule is in `skills/verify/references/generic-gate.md`.
- **Named subagents** for every independent check: `task-reviewer` (tier 1), the three refuters (tier 2) and `finding-verifier`, run in parallel with background `Task` and `task_wait` on pi, and `developer` for parallel-safe tasks.
- **Multiple-choice questions** at each decision: the lane when intent is unclear, where the work runs, the autopilot offer, clarify's questions, spec approval, decision-queue answers, landing options, a tier-2 merge, a weaker tier-2 review. The answer is recorded verbatim.
- **The approval mode.** marcsh tells the agent the session's approval mode each turn; the agents follow it (see Limits).
- **Session commands** the agents point you to: `/diff` to see the whole change, `/undo` to put back a turn's files before a commit, `/export` to keep the session transcript with the records, `/compact` before resuming a long build.

## Commands

Each command starts a turn as the agent it names (marcsh 0.4.0 or later; before that it runs as the selected agent) and expands to the skill shown. Arguments in brackets are optional.

| Command | Agent | Does |
| --- | --- | --- |
| `/ftd <ask>` | FTD | the lane, the feature document and the minimal loop |
| `/debug <symptom>` | FTD | the debug loop: reproduce, isolate, hypothesize, fix, verify |
| `/risk [base]` | FTD | the risk tier of the current diff, read-only |
| `/asdd <idea>` | ASDD | the dispatcher: routes to the phase that fits |
| `/spec <idea>` | ASDD | specify, then clarify, then your approval |
| `/plan [slug]` | ASDD | plan, tasks, analyze |
| `/build [slug]` | ASDD | implement, resuming from the progress file and `git log` |
| `/verify [slug]` | ASDD | verify in closing mode |
| `/review [slug or T<n>]` | ASDD | review of one task by its tier, or the closing review |
| `/ship [slug]` | ASDD | ship: checklist, explainer, three landing options |
| `/queue [slug]` | ASDD | show the decision queue and answer it |
| `/autopilot <idea>` | ASDD | spec to ship with one up-front yes |
| `/resume [slug]` | ASDD | rebuild the state from the session record and the progress file, and continue |

## What is in the pack

```text
agents/ftd.md, agents/asdd.md      the two primary agents (Tab, /agents)
agents/task-reviewer.md            subagents (mode: subagent), never in the Tab list:
agents/refuter-correctness.md        the frozen briefs of the reviewers and the worker
agents/refuter-security.md
agents/refuter-tests.md
agents/finding-verifier.md
agents/spec-reviewer.md
agents/developer.md
commands/                          the 13 entry-point commands (see Commands)
hooks/hooks.json, hooks/pre-bash   PreToolUse checks on Bash (and bg_start on pi), off until you enable them
hooks/lib/                         the hooks' POSIX sh and awk helpers, including sdd-root and risk-tier
scripts/                           checkout-only wrappers for hooks/lib/sdd-root and risk-tier (an installed
                                     pack exposes only skills/, commands/ and hooks/, so skills don't call them)
tests/                             the hook and script tests (sh tests/run.sh)
skills/ftd/                        the FTD lane
skills/asdd/                       the dispatcher, plus references/without-rsc-cli.md and references/marcsh.md (new)
skills/suggest/                    the lane decisor only (trimmed)
skills/constitution/ specify/ clarify/ plan/ tasks/ analyze/
skills/implement/ verify/ review/ ship/ debug/
.claude-plugin/plugin.json
```

The subagents are read-only except `developer`, which edits files and runs commands but never commits. The hooks run only `sh` and `git` on your machine, with no network and no `npx`. When they are on, they block a tier-2 push or PR without a passing spec linked to the branch and a recorded panel, a tier-2 merge by the agent (you merge in the forge), `gh pr merge` while a blocking decision is open, AI co-author trailers and "generated with" footers, and secrets in a commit or push. No MCP servers, no `allowed-tools` in any frontmatter, no symlinks.

## Adapted, copied, removed

**Copied as is** (method text, tables, templates, examples): the spec, plan and constitution templates, the specify elicitation reference, the generic gate, the per-task review brief, and the bodies of `specify`, `clarify`, `plan`, `tasks`, `analyze`, `debug`, `ftd`, `asdd`, `implement`, `verify`, `review`, `ship` outside the parts below. `implement/scripts/` (`task-brief`, `review-package`, `sdd-workspace`) are copied unchanged: they are plain shell and git.

**Adapted** (everywhere, in every skill):

- Frontmatter reduced to `name`, `description`, `tags`, `origin`. `recommends` and `profiles` (installer metadata) removed.
- Per-phase **model routing** (`models.*` in `config.yaml`, `references/model-routing.md`) removed. The session model is used.
- The **Spanish `Orientación (siempre)` compass block** and the `orient` voice removed. A short "plain sentences, end on the next step" rule lives in the agents instead.
- References to rsc skills that are not in the pack (`harness`, `init`, `orient`, `sdd-init`, `worktrees`, `parallel`, `idea-refinement`, `security-audit`, `deployment`, `code-review`, the stack skills) removed or rewritten to the project's own conventions. The user profile (`02-DOCS/wiki/harness/user-profile.md`) is now optional: read it if present, ask once if not.
- `config.yaml` (written by `sdd-init`) is now optional; test and verify commands come from the project's manifests and CI, and the generic gate is the normal path in `verify`.
- `.rsc/` state, `.rsc.json`, onboarding and the multi-target installer are removed or marked as not applicable.
- rsc's hooks are replaced by the pack's own, smaller set (`hooks/`): the tier-2 push, PR and merge gates, the blocking queue, authorship and secrets. They are off until the user enables them, so the text says "enforced when the pack hooks are on; otherwise held by discipline". The sello, the leave-branch guard and the post-merge cleanup have no hook here.
- The `refuter-*`, `finding-verifier` and `developer` subagents are shipped as marcsh subagents, with `task-reviewer` (rsc's per-task review brief) and `spec-reviewer` (the cold spec reader) added. Their role text moved out of the skills into the agent files, so the orchestrator hands over inputs and never paraphrases a brief. Only when no subagent can be started does a check run as a separate pass, and the record says it was not independent.
- Long commands, questions, the approval mode and marcsh's session commands are written in where the method needs them (`skills/asdd/references/marcsh.md`).

**Rewritten more heavily**: `suggest` (kept only the lane decisor), `review` (the sello section replaced by a note that it is unavailable; ledger and consolidation made manual; dispatch to the named subagents), `ship` (the guard and post-merge cleanup sections replaced by the pack hooks and manual steps), `implement` (steps b to d and the dispatch section), `ftd` (risk, escalation, branch rules), `implement/references/per-task-review.md` (now the inputs and dispatch; the brief is `agents/task-reviewer.md`).

**Kept in Spanish on purpose**: the four typed *Points to clarify* labels (`pregunta abierta`, `suposición tomada`, `decisión diferida`, `área no formulable`), the verification record labels (`NO-APLICA`, `HERRAMIENTA-AUSENTE`, `SUSTITUIDA`, `Capas no ejecutadas`) and a few quoted prompts. They are vocabulary the skills use consistently; the agent answers in the user's language.

**Not copied**: the `evals/` folders, `scripts/`, `manifest.json`, targets and tests of rsc-harness; `asdd/references/model-routing.md`. The pack's own `scripts/`, `hooks/` and `tests/` are new, written for marcsh.

**Kept opinions of the source**, flagged because they are not marcsh's: git authorship is always the human's (no `Co-Authored-By` for any AI, no "generated with" footer), and the feature documents live in `02-DOCS`, outside the code repository when a workspace folder sits above it.

## The rsc commands, call by call

The skills call `npx @ericrisco/rsc ...`. Each call was checked against rsc 4.1.2's source, and the standalone ones were run in a scratch git repository with no `.rsc.json`. The decision per call:

| Call (where it appears) | Works without rsc onboarding? | Decision |
| --- | --- | --- |
| `rsc risk [--base] [paths]` (ftd, asdd, tasks, implement, review, ship) | Yes, in a git repo. Needs paths, or a base branch with commits. Reads a path table and content patterns, no state. | Default is a manual rubric (`asdd/references/without-rsc-cli.md` section 1) with the same table. The CLI is named as an optional shortcut, only with the user's consent. |
| `rsc spec gate` (specify, asdd, ftd) | Yes. Reads `02-DOCS/wiki/sdd/specs/`. | Manual checklist of the template sections (section 2). Optional CLI shortcut. With the pack hooks on, the push hook runs the section check on the spec whose frontmatter says `branch: <current>` before a tier-2 push or PR. |
| `rsc review consolidate` (review, implement) | Yes. | Manual grouping and downgrade rules (section 4). |
| `rsc review ledger round/record/outcome/panel/stats` (asdd, review, implement, ship) | Runs, but writes `.rsc/review-ledger.jsonl` and the push gate that reads the panel record is a hook. | Ledger kept by hand in `progress/<slug>.md` (section 3). With the pack hooks on, the push hook reads the panel line there before a tier-2 push or PR; otherwise it is a record held by discipline. |
| `rsc review escapes` (review, ship, asdd) | Yes, needs commits. | `git log` on reverts plus a case file (section 5). |
| `rsc sello freeze/approve/block/budget/budget-check/status/off` (review, ship) | Runs and prints state, but nothing enforces it without hooks. | Removed. `review` says the sello is unavailable. The fix budget becomes a line count in the progress file. |
| `rsc main status` / `main unlock` (ftd, suggest, ship, asdd) | `status` runs and reports; `unlock` writes `.rsc/` markers and re-syncs rsc targets. | Removed. The agent judges whether the default branch looks protected and asks with the question tool (section 6). With the pack hooks on, the agent's tier-2 merge into the default branch is blocked. |
| `rsc worktrees` / `reap` (ship) | Tied to the rsc post-merge hook. | Manual `git worktree list` and `remove`, only for worktrees the agent made. |
| `rsc registry refresh` (implement) | No: builds `.rsc/skill-registry.json` from installed rsc skills. | Removed. |
| `rsc add`, `catalog`, `list`, `consult`, `capabilities`, `doctor`, `repair`, `reassess`, `sync`, `onboard` (suggest, constitution, specify) | Installer mechanics. | Removed with the parts of `suggest` that used them. |

`npx` downloads a third-party package, so no skill runs any of these silently.

## Limits

- **Hooks are opt-in and partial.** The pack's hooks block a tier-2 push or PR without a passing spec and a recorded panel, the agent's tier-2 merge, a merge with an open blocking decision, AI authorship trailers and secrets, but only after you enable them in `/agents`, and the agent cannot see whether they are on, so it holds the same lines by discipline either way. They check command text before it runs: a command they do not recognise, or a push made outside marcsh, passes. rsc's sealed reviews, its leave-branch guard and its post-merge cleanup have no hook here. A user who needs hard gates should also keep branch protection and required reviews on the forge.
- **Subagents need marcsh 0.4.0 or later to be named.** On 0.3.x the agent passes the subagent file's body as the prompt of a plain `Task`, which keeps the brief but not the subagent's read-only setting. Where no subagent can be started at all, the review is a separate pass by the same agent, which is weaker; at tier 2 the user decides, with a question, if that is enough.
- **Background work is pi's.** `bg_start`, background `Task` and `task_wait` exist only in interactive pi sessions; on Claude the engine's own background mode is used, and in Plan or `marcsh run` long commands get an explicit `timeout` instead. On pi a foreground command or subagent is stopped after 3 minutes; at most 4 background subagents run at once.
- **Questions need someone to answer.** In `marcsh run` (headless) questions are refused; the agents then park the decision or record an assumption, as in autopilot, and never read a refused question as a yes.
- **Commands need marcsh 0.4.0 or later to pick their agent.** Before that a pack command runs as the selected agent, and its skills load only if that agent is FTD or ASDD.
- **No stack skills.** The rsc FastAPI, Next.js, Go, Postgres, Flutter, design and security-audit skills are not in the pack. Verification uses the project's own commands.
- **Approval mode.** The agents follow marcsh's session approval mode (normal, auto or yolo; switch it with `/permissions`). Auto and yolo are a branch sandbox: they only apply on a feature branch, and marcsh pauses them on the default branch, so the agents then propose starting the feature in a git worktree. In auto, ordinary edits and commands need no chat yes; in yolo, committing finished work on that branch needs none either, and the agent says in one line what it committed. Push, PR, branch changes, merges (tier-2 merge approval included), spec approval, deleting a branch, force pushes and the git identity check keep the normal rules, and a commit on the default branch stays denied.
- **Skills load only for a turn that runs as a pack agent.** Under Build or Plan none of this is available, except through a pack command on marcsh 0.4.0 or later, which runs that turn as FTD or ASDD.
- **Working notes go in `02-DOCS/`.** The agents create it in the project folder when no workspace folder exists. Add it to `.gitignore` if the notes should not be committed.

## Credit

The method, the skills and most of their text are the work of **Eric Risco**: [rsc-harness](https://github.com/ericrisco/rsc-harness) (MIT, Copyright (c) 2026 Eric Risco), adapted from package `@ericrisco/rsc` version 4.1.2 (upstream tag `v4.1.2`, commit `f3765d35e91690c0c7e511447da6cd0176ab38e0`).

## License

MIT. See `LICENSE`. Eric Risco's copyright notice is kept for the adapted material.
