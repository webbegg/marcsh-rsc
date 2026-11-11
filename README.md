# marcsh-rsc

Two workflows for marcsh, packaged as an agent pack:

- **FTD** (Fast-Track Development): the lane for ordinary changes. One short feature document, tasks checked off only against observed proof, a minimal risk loop.
- **ASDD** (Agent Spec-Driven Development): the lane for big work. A spec the user approves, a plan, tasks, a per-task build and review loop scaled by risk, a decision queue, and a closing review.

Both come from [rsc-harness](https://github.com/ericrisco/rsc-harness) by Eric Risco (MIT) and are adapted to run under marcsh, which has no hooks and no `rsc` command line tool. See [Credit](#credit) and [Limits](#limits).

## Install

```text
/agents install <owner>/marcsh-rsc
```

(`<owner>` is not decided yet.) marcsh shows what the pack contains and asks before it enables anything. Updates are explicit: `/agents update <owner>/marcsh-rsc`.

Then pick **FTD** or **ASDD** with Tab or `/agents`. The pack's skills and commands reach the engine only while one of its two agents is selected.

## What each agent does

**FTD** (`agents/ftd.md`) is an always-on operating prompt. Every turn it first chooses a lane and says which: *answer* (read-only, nothing written), *FTD*, or *escalate to ASDD*. For FTD it writes a feature document at `02-DOCS/wiki/ftd/<slug>.md` before the first change (intent, scope, checklist, evidence, next step), checks tasks off only against observed output, computes the risk tier of the change, asks for one fresh-context review from tier 1, and asks where the work should run before it writes code on a branch that looks protected. It escalates to ASDD at tier 2 or when a change contradicts a recorded decision.

**ASDD** (`agents/asdd.md`) is the dispatcher of the chain: constitution, specify, clarify, plan, tasks, analyze, implement (verify and review inside every task), closing, ship. Artifacts go under `02-DOCS/wiki/sdd/`. The user approves the spec, answers the decision queue, and approves a tier-2 merge; everything else runs. It supports an up-front "take it all the way" (autopilot) that parks questions in the queue instead of stopping.

Neither agent sets a `model`: the session model is used.

## What is in the pack

```text
agents/ftd.md, agents/asdd.md
skills/ftd/            the FTD lane
skills/asdd/           the dispatcher, plus references/without-rsc-cli.md (new)
skills/suggest/        the lane decisor only (trimmed)
skills/constitution/ specify/ clarify/ plan/ tasks/ analyze/
skills/implement/ verify/ review/ ship/ debug/
.claude-plugin/plugin.json
```

No hooks, no MCP servers, no `commands/`, no `allowed-tools` in any frontmatter, no symlinks.

## Adapted, copied, removed

**Copied as is** (method text, tables, templates, examples): the spec, plan and constitution templates, the specify elicitation reference, the generic gate, the per-task review brief, and the bodies of `specify`, `clarify`, `plan`, `tasks`, `analyze`, `debug`, `ftd`, `asdd`, `implement`, `verify`, `review`, `ship` outside the parts below. `implement/scripts/` (`task-brief`, `review-package`, `sdd-workspace`) are copied unchanged: they are plain shell and git.

**Adapted** (everywhere, in every skill):

- Frontmatter reduced to `name`, `description`, `tags`, `origin`. `recommends` and `profiles` (installer metadata) removed.
- Per-phase **model routing** (`models.*` in `config.yaml`, `references/model-routing.md`) removed. The session model is used.
- The **Spanish `Orientación (siempre)` compass block** and the `orient` voice removed. A short "plain sentences, end on the next step" rule lives in the agents instead.
- References to rsc skills that are not in the pack (`harness`, `init`, `orient`, `sdd-init`, `worktrees`, `parallel`, `idea-refinement`, `security-audit`, `deployment`, `code-review`, the stack skills) removed or rewritten to the project's own conventions. The user profile (`02-DOCS/wiki/harness/user-profile.md`) is now optional: read it if present, ask once if not.
- `config.yaml` (written by `sdd-init`) is now optional; test and verify commands come from the project's manifests and CI, and the generic gate is the normal path in `verify`.
- `.rsc/` state, `.rsc.json`, onboarding, hooks and the multi-target installer are removed or marked as not applicable.
- The `refuter-*`, `finding-verifier` and `developer` subagents are not shipped. The text says what each does; where the engine can start a fresh-context subagent it should, otherwise the check runs as a separate pass and the record says it was not independent.

**Rewritten more heavily**: `suggest` (kept only the lane decisor), `review` (the sello section replaced by a note that it is unavailable; ledger and consolidation made manual), `ship` (the guard and post-merge cleanup sections replaced by manual steps), `implement` (steps b to d and the dispatch section), `ftd` (risk, escalation, branch rules).

**Kept in Spanish on purpose**: the four typed *Points to clarify* labels (`pregunta abierta`, `suposición tomada`, `decisión diferida`, `área no formulable`), the verification record labels (`NO-APLICA`, `HERRAMIENTA-AUSENTE`, `SUSTITUIDA`, `Capas no ejecutadas`) and a few quoted prompts. They are vocabulary the skills use consistently; the agent answers in the user's language.

**Not copied**: the `evals/` folders, `scripts/`, `manifest.json`, targets and tests of rsc-harness; `asdd/references/model-routing.md`.

**Kept opinions of the source**, flagged because they are not marcsh's: git authorship is always the human's (no `Co-Authored-By` for any AI, no "generated with" footer), and the feature documents live in `02-DOCS`, outside the code repository when a workspace folder sits above it.

## The rsc commands, call by call

The skills call `npx @ericrisco/rsc ...`. Each call was checked against rsc 4.1.2's source, and the standalone ones were run in a scratch git repository with no `.rsc.json`. The decision per call:

| Call (where it appears) | Works without rsc onboarding? | Decision |
| --- | --- | --- |
| `rsc risk [--base] [paths]` (ftd, asdd, tasks, implement, review, ship) | Yes, in a git repo. Needs paths, or a base branch with commits. Reads a path table and content patterns, no state. | Default is a manual rubric (`asdd/references/without-rsc-cli.md` section 1) with the same table. The CLI is named as an optional shortcut, only with the user's consent. |
| `rsc spec gate` (specify, asdd, ftd) | Yes. Reads `02-DOCS/wiki/sdd/specs/`. | Manual checklist of the template sections (section 2). Optional CLI shortcut. |
| `rsc review consolidate` (review, implement) | Yes. | Manual grouping and downgrade rules (section 4). |
| `rsc review ledger round/record/outcome/panel/stats` (asdd, review, implement, ship) | Runs, but writes `.rsc/review-ledger.jsonl` and the push gate that reads the panel record is a hook. | Ledger kept by hand in `progress/<slug>.md` (section 3). The panel line is a record, not a gate. |
| `rsc review escapes` (review, ship, asdd) | Yes, needs commits. | `git log` on reverts plus a case file (section 5). |
| `rsc sello freeze/approve/block/budget/budget-check/status/off` (review, ship) | Runs and prints state, but nothing enforces it without hooks. | Removed. `review` says the sello is unavailable. The fix budget becomes a line count in the progress file. |
| `rsc main status` / `main unlock` (ftd, suggest, ship, asdd) | `status` runs and reports; `unlock` writes `.rsc/` markers and re-syncs rsc targets. | Removed. The agent judges whether the default branch looks protected and asks (section 6). |
| `rsc worktrees` / `reap` (ship) | Tied to the rsc post-merge hook. | Manual `git worktree list` and `remove`, only for worktrees the agent made. |
| `rsc registry refresh` (implement) | No: builds `.rsc/skill-registry.json` from installed rsc skills. | Removed. |
| `rsc add`, `catalog`, `list`, `consult`, `capabilities`, `doctor`, `repair`, `reassess`, `sync`, `onboard` (suggest, constitution, specify) | Installer mechanics. | Removed with the parts of `suggest` that used them. |

`npx` downloads a third-party package, so no skill runs any of these silently.

## Limits

- **No hook enforcement.** rsc stops a tier-2 branch from being pushed without a spec that passes the gate and a recorded three-lens panel; it seals reviews to exact bytes; it denies unsafe merges; it retires worktrees after a merge. marcsh runs none of it. Here the agent holds those lines by discipline and says so. A user who needs the hard gates should keep branch protection and required reviews on the forge.
- **Subagents depend on the engine.** Independent-context reviews need an engine that can start subagents. Without it the review is a separate pass by the same agent, which is weaker; at tier 2 the user decides if that is enough.
- **No stack skills.** The rsc FastAPI, Next.js, Go, Postgres, Flutter, design and security-audit skills are not in the pack. Verification uses the project's own commands.
- **Skills load only with a pack agent selected.** Under Build or Plan none of this is available.
- **Working notes go in `02-DOCS/`.** The agents create it in the project folder when no workspace folder exists. Add it to `.gitignore` if the notes should not be committed.

## Credit

The method, the skills and most of their text are the work of **Eric Risco**: [rsc-harness](https://github.com/ericrisco/rsc-harness) (MIT, Copyright (c) 2026 Eric Risco), adapted from package `@ericrisco/rsc` version 4.1.2. The local reference checkout used for this adaptation had no commits, so no upstream commit hash could be read; the package version is the identifier. Pin a commit here when the upstream state is known.

## License

MIT. See `LICENSE`. Eric Risco's copyright notice is kept for the adapted material.
