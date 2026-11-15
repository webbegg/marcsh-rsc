# Using marcsh's tools

The skills name a few marcsh features at the points where the method needs them. This file states
each one once: long commands, subagents, questions, the pack hooks, the approval mode, the
session commands the user can type, and leftover processes. Features marked *pi* exist only in pi sessions; on Claude, the
engine's own equivalent is named.

## 1. Long commands

The rule is in `../../verify/references/generic-gate.md`, section "Long commands": focused RED and
GREEN tests in the foreground; full suites, builds, audits, `git bisect run`, `gh pr checks
--watch` and dev servers with `bg_start` on pi (the engine's background mode on Claude) or an
explicit `timeout`; the exit code from the background result.

## 2. Subagents

The pack ships its reviewers and its worker as named subagents. Their files are the frozen briefs:
the orchestrator hands over the inputs, never a paraphrase of the role.

| Subagent | File | Does | Permission |
| --- | --- | --- | --- |
| `task-reviewer` | `../../../agents/task-reviewer.md` | tier-1 review of one task | read-only |
| `refuter-correctness` | `../../../agents/refuter-correctness.md` | tier-2 lens: spec fidelity, correctness, contracts | read-only |
| `refuter-security` | `../../../agents/refuter-security.md` | tier-2 lens: untrusted input, authz, secrets | read-only |
| `refuter-tests` | `../../../agents/refuter-tests.md` | tier-2 lens: tests as evidence, criterion mapping | read-only |
| `finding-verifier` | `../../../agents/finding-verifier.md` | one blocker or should-fix: CONFIRMED, REFUTED or UNPROVEN | read-only |
| `spec-reviewer` | `../../../agents/spec-reviewer.md` | cold read of a spec before approval | read-only |
| `developer` | `../../../agents/developer.md` | one `[P]` task, TDD, no commit | build |

**How to start one.** Start the `<slug>` subagent with `Task` (`agent: "<slug>"`; on Claude the
same name is its `subagent_type`); give it exactly the inputs listed. To run several at once on pi
use `background: true` and collect them with `task_wait` (cancel with `task_cancel`); on Claude
issue the `Task` calls in parallel. If `Task` has no `agent` parameter (older marcsh), pass the
subagent file's body as the prompt instead. Only when no subagent can be started at all, run the
pass yourself and record that it was not independent.

- **The 3-minute limit.** On pi a foreground `Task` is stopped after 3 minutes. Start reviewers
  and workers with `background: true` whenever the session offers it, even a single one, and wait
  with `task_wait` (it waits at most a little under 3 minutes per call; call it again until the
  result is in). At most 4 background subagents run at once: queue the rest.
- **Wait inside the turn.** Collect every reviewer before you consolidate. Never end the turn to
  ask whether to continue.
- **What a subagent cannot do.** A background subagent cannot start background subagents or
  background terminals, so its long commands need an explicit `timeout`. A read-only one runs no
  commands at all: it traces by reading, and names the command the orchestrator should run.
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
ratification, decision-queue answers, landing options, a tier-2 merge, a weak tier-2 review, and
`npx` consent.

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
- `gh pr merge` while a `- [blocking]` entry is open in the decision queue;
- a commit or push that carries an AI co-author trailer or a "generated with" footer;
- a commit or push whose diff matches the secrets pattern of `ship`.

You cannot see whether they are on. Hold every one of these lines by discipline anyway: the hooks
are a second lock, not the first. Where the skills say "enforced when the pack hooks are on;
otherwise held by discipline", that is what it means. A hook block arrives as a tool error with the
reason: fix the cause it names, and never reach the same effect another way.

## 5. The approval mode

marcsh tells the model the session's approval mode each turn (normal, auto or yolo, paused on the
default branch, and whether Plan is on); older marcsh adds a line only for auto and yolo, so no
line means normal. The agents' "Approval mode" rule says what each mode relaxes and what it never
relaxes. In Plan nothing is written and no command runs: answer, read and plan only.

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

The rule is in `../../verify/references/generic-gate.md`, section "Stop what you start": servers,
browsers, watchers and `cargo run`/`node` processes go through `bg_start` and are stopped with
`bg_kill` once the proof is taken, unless the user asked to keep them; before closing a task, a
turn or a verification that ran processes, check for leftovers and stop the ones this work
started; the evidence says "no leftover processes" or what was kept and why.

- **What marcsh gives.** Every process marcsh's tools start carries `MARCSH_SESSION=<id>` in its
  environment (on pi `bash` often `MARCSH_CALL=<tool call id>` too). The user sees the live ones
  in `/ps` ("Leftover processes", `x` stops one) and the status line counts them (`N leftover ·
  /ps`). Nothing is stopped automatically; background terminals still stop when the session is
  left or marcsh quits.
- **On pi** (*pi*): `proc_list` lists this session's live leftover processes (pid, command, age,
  memory); `proc_stop` with a list of pids stops only this session's marked processes. `proc_list`
  works in Plan; `proc_stop` does not.
- **On Claude**, and on pi when `proc_list` is not offered: `sh <verify skill dir>/scripts/leftovers`
  (the `verify` skill's `scripts/leftovers`, `../../verify/scripts/leftovers` from this file)
  lists the same processes, one line each (`pid  age  rssMB  command`); `--count` prints only the
  number; `--stop <pid>...` re-checks each pid's marker, sends TERM, waits up to 2 s, then KILL,
  and refuses any pid without the marker. Claude's Bash children inherit the marker, so the script
  sees what they started.
- **Limits.** `proc_list` and `proc_stop` need marcsh with leftover tracking (the next marcsh
  release). Without it `MARCSH_SESSION` is not set and the script says so: the check is not run;
  stop by hand only what you started yourself. On macOS the system hides the environment of
  Apple's own binaries (`sh`, `sleep`) from the script, so it cannot see those; third-party
  programs such as `node` it can.
