# marcsh-rsc

Two workflows for marcsh, packaged as an agent pack:

- **FTD** (Fast-Track Development): the lane for ordinary changes. One short feature document, tasks checked off only against observed proof, a minimal risk loop.
- **ASDD** (Agent Spec-Driven Development): the lane for big work. A spec the user approves, a plan, tasks, a per-task build and review loop scaled by risk, a decision queue, and a closing review.

Both come from [rsc-harness](https://github.com/ericrisco/rsc-harness) by Eric Risco (MIT) and are adapted to run under marcsh, without the `rsc` command line tool: named reviewer subagents, entry-point commands, background work for long commands, multiple-choice questions at every gate, and optional hooks for the hard gates. See [Credit](#credit) and [Limits](#limits).

Requires marcsh 0.4.0 or later: named subagents, agent-aware commands, the approval-mode line and leftover-process tracking all need it. On older marcsh a command runs as the selected agent, every review is a separate pass by the same agent (recorded as not independent), and the leftover check is recorded as not run.

## Install

```text
/agents install webbegg/marcsh-rsc
```

marcsh shows what the pack contains and asks before it enables anything. Updates are explicit: `/agents update webbegg/marcsh-rsc`.

Then pick **FTD** or **ASDD** with Tab or `/agents`, or start a turn with one of the pack's [commands](#commands), which runs as the agent it names. The pack's skills load only for a turn that runs as one of its two agents.

The pack's hooks are off after the install. To turn them on, run `/agents hooks webbegg/marcsh-rsc`, scroll the review to the end and choose **Enable**; `/agents hooks webbegg/marcsh-rsc off` turns them off (see marcsh's pack hooks documentation). They are pinned to the commit you reviewed; an update turns them off until you review again.

## What each agent does

**FTD** (`agents/ftd.md`) is an always-on operating prompt. Every turn it first chooses a lane and says which: *answer* (read-only, nothing written), *FTD*, or *escalate to ASDD*. For FTD it writes a feature document at `02-DOCS/wiki/ftd/<slug>.md` before the first change (intent, scope, checklist, evidence, next step), checks tasks off only against observed output, computes the risk tier of the change, asks for one fresh-context review from tier 1, and, on the default branch (where marcsh blocks every commit), asks whether the work runs on a new branch or in a worktree before it writes code. It escalates to ASDD at tier 2 or when a change contradicts a recorded decision.

**ASDD** (`agents/asdd.md`) is the dispatcher of the chain: constitution, specify, clarify, plan, tasks, analyze, implement (verify and review inside every task), closing, ship. Artifacts go under `02-DOCS/wiki/sdd/`. The user approves the spec, answers the decision queue, and approves a tier-2 merge; everything else runs. It supports an up-front "take it all the way" (autopilot) that parks questions in the queue instead of stopping.

Neither agent sets a `model`: the session model is used.

Both agents use marcsh's own features where the method needs them (`skills/asdd/references/marcsh.md`):

- **Long commands in the background.** Only focused tests and quick commands run in the foreground; everything else runs in the background or with an explicit `timeout`, so the 3-minute limit never turns a check into a false result. The rule is in `skills/verify/references/generic-gate.md`, "Long commands".
- **Stop what you start, and only with your yes.** Servers, browsers and watchers start in the background and stop once the proof is taken. Before closing a task, a turn or a verification, the agent lists leftover processes (`proc_list` on pi; otherwise the pack script `skills/verify/scripts/leftovers`). It never stops one without your yes: on pi `proc_stop` asks you itself; otherwise the agent asks with the question tool, never suggests a process flagged "possibly yours", and runs `leftovers --stop` with the ones you chose. Subagents only report their leftovers. The rule is in `skills/asdd/references/marcsh.md` section 7.
- **Named subagents** for every independent check: `task-reviewer` (tier 1), the three refuters (tier 2) and `finding-verifier`, run in parallel with background `Task` and `task_wait` on pi, and `developer` for parallel-safe tasks.
- **Multiple-choice questions** at each decision: the lane when intent is unclear, where the work runs, the autopilot offer, clarify's questions, spec approval, decision-queue answers, landing options, a tier-2 merge, a weaker tier-2 review. The answer is recorded verbatim.
- **The approval mode.** marcsh tells the agent the session's approval mode each turn; the agents follow it (see Limits).
- **Session commands** the agents point you to: `/diff` to see the whole change, `/undo` to put back a turn's files before a commit, `/export` to keep the session transcript with the records, `/compact` before resuming a long build.

## Commands

Each command starts a turn as the agent it names (marcsh 0.4.0 or later) and expands to the skill shown. Arguments in brackets are optional. The review command is `/sdd-review` so it never collides with an engine's own `/review`; if another command already uses one of these names, marcsh lists the pack's as `/marcsh-rsc:<name>`.

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
| `/sdd-review [slug or T<n>]` | ASDD | review of one task by its tier, or the closing review |
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
tests/                             the hook and script tests (sh tests/run.sh) and the leftovers
                                     script tests (sh tests/leftovers.sh)
skills/ftd/                        the FTD lane
skills/asdd/                       the dispatcher, plus references/without-rsc-cli.md and references/marcsh.md (new)
skills/suggest/                    the lane decisor only (trimmed)
skills/constitution/ specify/ clarify/ plan/ tasks/ analyze/
skills/implement/ verify/ review/ ship/ debug/
skills/verify/scripts/leftovers    lists this session's leftover processes, stops the ones you chose (POSIX sh, no network)
.claude-plugin/plugin.json
```

The subagents are read-only except `developer`, which edits files and runs commands but never commits. The hooks run only `sh` and `git` on your machine, with no network and no `npx`. When they are on, they block a tier-2 push or PR without a passing spec linked to the branch and a recorded panel, a tier-2 merge by the agent (you merge in the forge), `gh pr merge` while a blocking decision is open, a push that deletes the default branch (`git push origin :main`, `--delete main`; that is left to you), AI co-author trailers and "generated with" footers, and secrets in a commit or push. No MCP servers, no `allowed-tools` in any frontmatter, no symlinks.

### How the hooks read a command

- **Per refspec.** A push is judged on what it pushes, not on the checked-out branch: `git push origin feat/x` from `main` checks `feat/x`.
- **A push to the default branch is a merge.** A destination of the default branch (`feat/x:main`, `HEAD:main`, or `main` itself when it holds new work) is blocked at tier 2 like `gh pr merge`.
- **Many branches at once.** `--all`, `--branches`, `--mirror` and glob refspecs check every local branch that differs from origin's copy; more than 20 are blocked (push them one at a time).
- **Wrappers and nested shells.** The hooks see through wrappers (`timeout`, `xargs`, `env -S`, `sudo`, `nice`, `stdbuf`, `script`, `flock`, `find -exec`, `parallel` and others), commands a shell reads on stdin (`sh <<EOF`, `bash <<<`, `echo ... | sh`, `cat <<EOF | bash`, `cat FILE | sh`, `sh < FILE`), and scripts run with `sh FILE`, `source` or `.` when they are inside the project (a file outside it is not read; a note says so).
- **Limits per command.** One command may hold at most 20 gated git calls; more are blocked (split the command).
- **Cost.** The cost of a push does not grow with its new commits, and the refspecs of one command are checked together (when they share one merge base with the default branch, the same few git calls for all of them). The verdicts stop at the first block.
- **Deadline.** If the checks haven't finished after 8 seconds, the hook blocks the call instead of running into marcsh's hook timeout: on a very slow machine, split the command.
- **Secrets.** The check flags concrete key formats (AWS, GitHub, Slack, Stripe live keys, private key blocks, JWTs, Google API keys) and a quoted literal of 12 or more characters assigned to a `password`, `secret`, `token` or `api_key` name. It skips URLs, paths, prose, identifiers and placeholders. In `.env` files it also flags unquoted values.

## Adapted, copied, removed

**Copied as is** (method text, tables, templates, examples): the spec, plan and constitution templates, the specify elicitation reference, and the bodies of `specify`, `clarify`, `plan`, `tasks`, `analyze`, `debug`, `ftd`, `asdd`, `implement`, `verify`, `review`, `ship` outside the parts below. `implement/scripts/task-brief` is copied unchanged.

**Adapted files**: the generic gate (`verify/references/generic-gate.md`: the long-command rule added), `implement/scripts/review-package` (plain diff output, no external diff tools) and `implement/scripts/sdd-workspace` (the scratch folder without `02-DOCS`). The scripts stay plain shell and git.

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
| `rsc main status` / `main unlock` (ftd, suggest, ship, asdd) | `status` runs and reports; `unlock` writes `.rsc/` markers and re-syncs rsc targets. | Removed. The agent never works on the default branch (marcsh blocks commits there) and asks with the question tool where the work runs (section 6); it judges whether the default branch looks protected only for the landing options. With the pack hooks on, the agent's tier-2 merge into the default branch is blocked. |
| `rsc worktrees` / `reap` (ship) | Tied to the rsc post-merge hook. | Manual `git worktree list` and `remove`, only for worktrees the agent made. |
| `rsc registry refresh` (implement) | No: builds `.rsc/skill-registry.json` from installed rsc skills. | Removed. |
| `rsc add`, `catalog`, `list`, `consult`, `capabilities`, `doctor`, `repair`, `reassess`, `sync`, `onboard` (suggest, constitution, specify) | Installer mechanics. | Removed with the parts of `suggest` that used them. |

`npx` downloads a third-party package, so no skill runs any of these silently.

## Limits

- **Hooks are opt-in and partial.** The pack's hooks block a tier-2 push or PR without a passing spec and a recorded panel, the agent's tier-2 merge, a merge with an open blocking decision, AI authorship trailers and secrets, but only after you enable them in `/agents`, and the agent cannot see whether they are on, so it holds the same lines by discipline either way. They check command text before it runs: a command they do not recognise, or a push made outside marcsh, passes. When a shell reads its commands from a program they cannot see through (`curl ... | sh`), any line of the command that holds `git ... push|commit|merge` or `gh ... pr` is treated as that command, which is the conservative choice. In a command over 256 KB, only the lines that could hold a gated call are read. Without `git` on `PATH`, they only leave a note. rsc's sealed reviews, its leave-branch guard and its post-merge cleanup have no hook here. A user who needs hard gates should also keep branch protection and required reviews on the forge.
- **Subagents need marcsh 0.4.0 or later.** Without `agent` on `Task`, or where no subagent can be started at all, the review is a separate pass by the same agent, recorded as not independent, which is weaker; at tier 2 the user decides, with a question, if that is enough.
- **Background work is pi's.** `bg_start`, background `Task` and `task_wait` exist only in interactive pi sessions; on Claude the engine's own background mode is used. Where there is none (headless `marcsh run`, a background subagent), long commands get an explicit `timeout`, no server or watcher is started (its runtime proof is recorded as not run), and subagent work is kept under 3 minutes. Plan runs no commands. On pi a foreground command or subagent is stopped after 3 minutes; at most 4 background subagents run at once.
- **Leftover processes need marcsh 0.4.0 or later.** `proc_list` and `proc_stop`, `/ps`'s "Leftover processes" and the `N leftover` status count, and the `MARCSH_SESSION` marker the script looks for, need it. Without them the script says the marker is not set, and the agent records the check as not run. A process you open through something a tool call started (an editor's terminal, a tmux pane) can carry the marker too; it is flagged "possibly yours", which is a hint, not a guarantee. On macOS the system hides the environment of Apple's own binaries (`sh`, `sleep`) from `ps -E`, so the script does not see those; third-party programs such as `node` it does. Nothing is stopped automatically, and nothing is stopped without your yes.
- **Questions need someone to answer.** In `marcsh run` (headless) questions are refused; the agents then park the decision or record an assumption, as in autopilot, and never read a refused question as a yes.
- **Commands need marcsh 0.4.0 or later to pick their agent.** On older marcsh a pack command runs as the selected agent, and its skills load only if that agent is FTD or ASDD.
- **No stack skills.** The rsc FastAPI, Next.js, Go, Postgres, Flutter, design and security-audit skills are not in the pack. Verification uses the project's own commands.
- **Approval mode.** The agents follow marcsh's session approval mode (normal, auto or yolo; switch it with `/permissions`). Auto and yolo are a branch sandbox: they only apply on a feature branch, and marcsh pauses them on the default branch, so the agents then propose starting the feature in a git worktree. In auto, ordinary edits and commands need no chat yes; in yolo, committing finished work on that branch needs none either, and the agent says in one line what it committed. Push, PR, branch changes, merges (tier-2 merge approval included), spec approval, deleting a branch, force pushes and the git identity check keep the normal rules, and a commit on the default branch stays denied.
- **Skills load only for a turn that runs as a pack agent.** Under Build or Plan none of this is available, except through a pack command on marcsh 0.4.0 or later, which runs that turn as FTD or ASDD.
- **Working notes go in `02-DOCS/`.** The agents create it in the project folder when no workspace folder exists. Add it to `.gitignore` if the notes should not be committed.

## Credit

The method, the skills and most of their text are the work of **Eric Risco**: [rsc-harness](https://github.com/ericrisco/rsc-harness) (MIT, Copyright (c) 2026 Eric Risco), adapted from package `@ericrisco/rsc` version 4.1.2 (upstream tag `v4.1.2`, commit `f3765d35e91690c0c7e511447da6cd0176ab38e0`).

## License

MIT. See `LICENSE`. Eric Risco's copyright notice is kept for the adapted material.
