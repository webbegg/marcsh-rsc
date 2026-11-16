# Using marcsh's tools

The skills name a few marcsh features at the points where the method needs them. This file states
each rule once: long commands, subagents, questions, the pack hooks, the approval mode, the
session commands the user can type, and leftover processes. Elsewhere the pack keeps a one-line
summary and a pointer here. Features marked *pi* exist only in pi sessions; on Claude, the
engine's own equivalent is named. Everything here needs marcsh 0.4.0 or later.

## 1. Long commands

The rule is in `../../verify/references/generic-gate.md`, section "Long commands". In short: only
focused tests and quick commands run in the foreground; everything else runs in the background or
with an explicit `timeout`, servers and watchers only in the background, and the exit code comes
from the background result.

## 2. Subagents

The pack ships its reviewers and its worker as named subagents. Each one carries its frozen brief:
the orchestrator hands over the inputs, never a paraphrase of the role.

| Subagent | Does | Permission |
| --- | --- | --- |
| `task-reviewer` | tier-1 review of one task; in closing mode, of the whole branch | read-only |
| `refuter-correctness` | tier-2 lens: spec fidelity, correctness, contracts | read-only |
| `refuter-security` | tier-2 lens: untrusted input, authz, secrets | read-only |
| `refuter-tests` | tier-2 lens: tests as evidence, criterion mapping | read-only |
| `finding-verifier` | one blocker or should-fix: CONFIRMED, REFUTED or UNPROVEN | read-only |
| `spec-reviewer` | cold read of a spec before approval | read-only |
| `developer` | one `[P]` task, TDD, no commit | build |

**How to start one (the dispatch rule).** Start the `<slug>` subagent with `Task` (`agent:
"<slug>"`; on Claude the same name is its `subagent_type`) and give it exactly the inputs its skill
lists. To run several at once on pi use `background: true` and collect them with `task_wait`
(cancel with `task_cancel`); on Claude issue the `Task` calls in parallel. The read-only ones
change nothing and run no commands: when a finding needs a run, you run it. If `Task` has no
`agent` parameter (marcsh before 0.4.0) or no subagent can be started at all, run the pass
yourself, read-only (change no file while you review), from the listed inputs only, and record
that it was not independent.

- **The 3-minute limit.** On pi a foreground `Task` is stopped after 3 minutes, and `Task` has no
  timeout parameter. Start reviewers and workers with `background: true` whenever the session
  offers it, even a single one, and wait with `task_wait` (it waits at most a little under 3
  minutes per call; call it again until the result is in). At most 4 background subagents run at
  once: queue the rest. Where there is no background `Task` (headless `marcsh run`), keep each
  subagent's work well under 3 minutes (one task, one finding), or run the pass yourself and
  record that it was not independent.
- **Wait inside the turn.** Collect every subagent before you consolidate. Never end the turn to
  ask whether to continue.
- **What a subagent cannot do.** A background subagent cannot start background subagents or
  background terminals, so it starts no servers or watchers and gives longer commands an explicit
  `timeout` (section 1). No subagent gets `proc_list` or `proc_stop`, and none stops a leftover
  process: it lists them and reports them in its result, and you ask and stop after it returns
  (section 7).
- **Approvals still apply.** A subagent's tool calls ask like the parent's, in the approval prompt
  labelled `Background subagent: <description>`; the pack hooks apply to it too.
- **The weak fallback is the exception.** At tier 2, a review run as a separate pass by the same
  agent is weaker; ask the user with the question tool whether it is enough (section 3), and
  record the answer.

## 3. Questions

marcsh gives the model a multiple-choice question tool (`AskUserQuestion`; on Claude its native
tool): one to four questions, each with a short header and two or more options with a description.
Use it at every decision point the skills name: the lane when change intent is unclear, where the
work runs, the autopilot offer, the clarify questions (one per call), spec approval, constitution
ratification, decision-queue answers, landing options, a tier-2 merge, a weak tier-2 review, which
leftover processes to stop, and `npx` consent.

- **Recommendation first.** Put your recommended option first and add "(recommended)" to its
  label. Each option's description says its consequence.
- **One decision per question.** A question that also approves something else is two questions.
  Spec approval and tier-2 merge approval are always their own question, never folded into another.
- **Record the answer verbatim**, with the question, where the skill says (the spec's `status:`
  and `## Clarifications`, the decision-queue entry, the progress file, `decisions.md`). An
  answer typed into "Other" is recorded as typed.
- **Typed confirmations stay typed.** Discarding a branch still needs the literal
  `yes, delete <branch>` in the user's own message; a picked option is not enough.
- **No one to ask.** In `marcsh run` (headless) questions are refused, and in autopilot nobody is
  asked between phases. Then do what the skill says for autopilot: record a `suposición tomada`,
  or park the item in the decision queue. A refused question is never an approval.

## 4. The pack hooks

The pack ships `hooks/hooks.json`: POSIX `sh` checks that run before a `Bash` command (on pi also
before `bg_start`). They are **off until the user enables them** in marcsh's `/agents` hooks
review. When they are on they block:

- a push or PR of a tier-2 branch without a spec that passes the gate and records `branch:
  <branch>` in its frontmatter, or without the panel line in `progress/<slug>.md`;
- a merge of a tier-2 change (`gh pr merge`, `git merge` into the default branch): the human merges
  in the forge;
- `gh pr merge` while a `- [blocking]` entry is open in the decision queue (a `- [closed]` entry
  does not block);
- a push that deletes the default branch;
- a commit or push that carries an AI co-author trailer or a "generated with" footer;
- a commit or push whose diff matches the secrets pattern of `ship`.

You cannot see whether they are on. Hold every one of these lines by discipline anyway: the hooks
are a second lock, not the first. Where the skills say "enforced when the pack hooks are on;
otherwise held by discipline", that is what it means. rsc's sealed reviews and branch guards have
no hook here; say so plainly when a gate you name is not mechanically enforced. A hook block
arrives as a tool error with the reason: fix the cause it names, and never reach the same effect
another way.

## 5. The approval mode

marcsh tells the model the session's approval mode in the system prompt each turn, and whether
Plan is on; no such line means normal. The wording of that line changes between releases: act on
the mode it names, not on its exact words.

- **Plan.** Write nothing and run nothing: answer, read and plan only (`proc_list` is the one
  process tool offered).
- **Normal.** Every rule of the agent stands.
- **AUTO** (active on a feature branch). Ordinary edits and commands need no chat confirmation, so
  do not ask before running them. Commits and delivery keep the agent's rules.
- **YOLO** (active on a feature branch). As AUTO, and committing finished work on the current
  feature branch needs no chat yes; say in one line what was committed.
- **Paused** (the folder is on the default branch, a detached HEAD or no repository). Work as in
  normal. Before the first code change, propose with the question tool to start the feature in a
  worktree, `git worktree add ../<repo>-worktrees/<slug> -b <type>/<slug>` (marcsh asks before it
  runs), then tell the user to open marcsh in that folder (`cd ../<repo>-worktrees/<slug> &&
  marcsh`), because this session stays in its folder. If they prefer, a plain feature branch in
  this folder (`git switch -c <type>/<slug>`) also activates the mode.
- **Never relaxed in any mode.** Push, PR, creating or switching branches and worktrees (marcsh
  asks for remote and branch-leaving actions too), merges (tier-2 merge approval included), spec
  approval and constitution ratification, deleting a branch or discarding work, force pushes, the
  git identity check, stopping a process (section 7), and anything marcsh still asks about. A
  tier-2 branch still waits for the spec gate and the human's yes to the merge.
- **A commit on the default branch is blocked in every mode.** Start a feature branch or a
  worktree first (`without-rsc-cli.md` §6).
- **Headless.** In `marcsh run` every ask is denied. A denied action is never an approval.

## 6. Session commands the user can type

The model cannot run these; point the user to them where they help, one line each.

- **`/diff`** shows every file change since the session's first turn. Offer it as evidence before
  a commit or a review ("type `/diff` to see the whole change"), and cite it in the FTD Evidence
  when the user checked it.
- **`/undo`** puts back the files the last turn changed (repeat for earlier turns; `/redo`
  re-applies). It is the rollback route for a turn that went wrong before anything was committed.
  It does not rewind the conversation and asks before overwriting files changed since. After a
  commit, roll back with git (`git revert`) instead.
- **`/export`** writes the session transcript to a file (`/export md <path>`; the folder must
  exist, and a relative path is relative to the project folder). Suggest it when a session record
  is written (`02-DOCS/wiki/sdd/sessions/`), and for a tier-2 run whose reasoning the human may want
  to audit.
- **`/compact`** compacts the conversation. Suggest it before resuming a long `implement` run;
  after it, rebuild state from `progress/<slug>.md` and `git log`, never from memory.

## 7. Processes

A process a check starts and nobody stops (a dev server, a browser, a watcher, `cargo run`, a
`node` process) keeps using memory long after the proof is taken. This is the one rule for them.

- **Start them in the background, stop them after the proof.** Servers, browsers, watchers and
  `cargo run`/`node` processes start only in the background (`bg_start` on pi; on Claude, the Bash
  tool's background option), never `cmd &` inside a foreground call, and where there is no
  background mode they are not started (section 1). Stop each one once its proof is taken
  (`bg_kill` on pi; on Claude, the engine's own tool for stopping a background shell), unless the
  user asked to keep it running.
- **Browsers (Playwright, Chrome).** Close the browser or context in the test code itself
  (`browser.close()` in a `finally` or `afterAll`): a run that crashed leaves the browser and its
  helper processes behind.
- **Check before you close.** Before closing a task, a turn or a verification that ran processes,
  list the leftovers: `proc_list` on pi (it runs without asking); on Claude, in a subagent, or when
  `proc_list` is not offered, `sh <verify skill dir>/scripts/leftovers` (the file is
  `../../verify/scripts/leftovers` from this one).
- **Never stop a process without the user's yes.**
  - On pi, use `proc_stop` with the pids. marcsh asks the user itself, in every approval mode,
    yolo included, with no "always", and shows each process, flagged "possibly yours" when it may
    be theirs. Never include a possibly-yours one unless the user named it.
  - Otherwise (Claude, or no `proc_stop`), ask with the question tool which ones to stop, one
    option per process (its pid, age and command) plus "Stop none", and never suggest a
    possibly-yours one. Then run `sh <verify skill dir>/scripts/leftovers --stop <pid:startkey>...`
    with exactly the ones the user chose; add `--confirmed` only when they explicitly chose a
    possibly-yours one.
  - Subagents (`developer` and every other) only list and report their leftovers in their result.
    The orchestrator asks and stops after they return.
  - No one to ask (headless `marcsh run`, autopilot): stop nothing; list what is still running in
    the record for the user.
- **Record it.** The evidence (the FTD feature document, the ASDD progress file, the verification
  record) says "no leftover processes", or names what still runs, what the user chose to stop, and
  why the rest was kept.
- **What the script shows.** One line per process, `<pid>:<startkey>  <age>  <rssMB>  <command>`
  (secret-looking values hidden), with ` [possibly yours: <reason>]` appended when it may be the
  user's. It never lists what is still under marcsh (running tool calls, background terminals, MCP
  servers) or what the pack hooks started. `--count` prints only the number. `--stop` re-checks
  each process right before signalling it, stops only this session's marked processes, refuses a
  possibly-yours one unless `--confirmed` is added, and reports `stopped` or `not stopped:
  <reason>` for each.
- **What marcsh gives.** Every process marcsh's tools start carries `MARCSH_SESSION=<id>` in its
  environment, and passes it on to whatever it starts. The user sees the live leftovers in `/ps`
  ("Leftover processes", `x` stops one) and the status line counts them (`N leftover · /ps`).
  Nothing is stopped automatically; background terminals still stop when the session is left or
  marcsh quits.
- **Not every marked process is yours.** Because the marker is passed on, a program the user later
  opens through something a tool call started (an editor's terminal, a tmux pane) can carry it
  too. "Possibly yours" flags such a process; the flag is a hint, not a guarantee.
- **Limits.** Without leftover tracking (marcsh before 0.4.0) `MARCSH_SESSION` is not set and the
  script says so: the check is **not run**; say so, and stop only the background commands you
  started yourself (first bullet). On macOS the system hides the environment of Apple's own binaries (`sh`, `sleep`) from
  the script, so it cannot see those; third-party programs such as `node` it can.
