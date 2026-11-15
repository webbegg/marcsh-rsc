# Working without the rsc CLI

Adapted for marcsh. The rsc harness runs a command line tool (`npx @ericrisco/rsc ...`) and hooks
around these skills. This pack does not install the tool, and its own hooks cover only some of
rsc's gates (the tier-2 push, PR and merge gates, the blocking queue, authorship and secrets; see
`marcsh.md` §4): enforced when the pack hooks are on; otherwise held by discipline. Every check the
skills name is done by hand here, with the same rules. Nothing below needs onboarding, `.rsc/` or
`.rsc.json`.

Each section says what the rsc call did and how to do it yourself. Where the call works on its own,
that is said too, as an optional shortcut.

## Optional shortcut: the standalone calls

Four rsc calls work in any git repository with no setup: `risk`, `spec gate`, `review consolidate`
and `review ledger` (plus `review escapes`). They were checked against the rsc source in a scratch
repository with no `.rsc.json`. Two details: `risk` needs paths on the command line or a base
branch with commits, and `review ledger` writes `.rsc/review-ledger.jsonl` in the project (local,
not meant to be committed). Run them only if the user has Node, says yes, and accepts that `npx`
downloads a third-party package from npm on first use. Ask with the question tool (`marcsh.md`
§3), the manual form as the recommended option. Never run them silently. If any of that is
missing, use the manual forms below. The manual forms are the default.

Calls that need the rsc install and have no use here: `sello` (freeze, approve, block, budget,
status), `main status` / `main unlock`, `worktrees`, `registry`, `add`, `catalog`, `consult`,
`capabilities`, `doctor`, `repair`, `reassess`, `onboard`, `sync`. If a skill still names one, skip
it and use the equivalent below.

## 1. Risk tier (replaces `rsc risk`)

The tier says how much review a change needs. The change sets it, never the author. It is computed
from the paths touched and from what the diff adds.

**Get the paths.** Task or branch diff: `git diff --name-only --no-renames <base>...HEAD`, plus
uncommitted work (`git status --short`) and untracked files. Before the work exists (a forecast in
`tasks`), use the paths the task is expected to touch. Count both sides of a rename.

**Score each path by the highest row it matches.** A path that matches nothing is tier 1.

| Class | Matches (case-insensitive) | Tier |
| --- | --- | --- |
| docs | under `docs/` or `doc/`; `*.md`, `*.mdx`, `*.txt`, `*.rst`; `LICENSE`; `CHANGELOG*` | 0 |
| secrets | `.env`, `.env.*`; a `secret`/`secrets`/`credential`/`credentials` folder or name; `*.pem`, `*.key`, `*.p12`, `*.pfx` | 2 |
| auth | a path part named `auth`, `authn`, `authz`, `login`, `session`, `oauth`, `sso` (folder or file stem) | 2 |
| ci | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile` | 2 |
| migrations | a `migration` or `migrations` folder | 2 |
| billing | a path part named `billing`, `payment`, `payments`, `checkout`, `stripe` | 2 |
| agent config | `CLAUDE.md`, `.claude/`, any agent or workflow configuration the project treats as its own rules | 2 |
| anything else | ordinary code, config, tests | 1 |

**Then read what the diff adds** (added lines only; skip docs, tests, fixtures, lockfiles, minified
files and comment lines, except for secrets, which count everywhere). One hit makes the change
tier 2 wherever the file lives:

- **auth**: hashing or verifying a password (`bcrypt`, `argon2`, `scrypt`, `pbkdf2`,
  `password_hash`), signing or verifying a token (`jwt.sign`, `jwt.verify`), `timingSafeEqual`,
  `createHmac`, issuing a session or setting a session or auth cookie, `passport.authenticate`,
  `getServerSession`, `createSession`.
- **billing**: creating or changing payment intents, charges, refunds, subscriptions or invoices;
  reading `STRIPE_*`, `PAYPAL_*` or similar keys.
- **migrations**: `ALTER TABLE`, `DROP TABLE`, `DROP COLUMN`, `CREATE TABLE`, `ADD COLUMN`,
  `RENAME COLUMN`.
- **secrets**: a private key block, an AWS access key id (`AKIA...`), a live payment key
  (`sk_live_...`), a GitHub token (`ghp_...`).

**The tier is the highest across all paths and hits.** State it in one line with the reason, for
example: `tier 2 (auth: src/login/handler.ts; password hash added in src/app.js)`.

| Tier | Review | Who approves |
| --- | --- | --- |
| 0 | none; the mandatory controls still run | nobody |
| 1 | one fresh-context reviewer | the reviewer's verdict plus the user's normal flow |
| 2 | three lenses: correctness, security, tests | **the user**, explicitly. An agent's approval never counts |

**Rules that stay.** The agent does not pick its own tier and does not argue it down. When the
user's project lists extra always-human paths (in `REVIEW.md` or the constitution), treat them as
tier 2. With nothing to classify, say so; do not default to 0.

**The push gate.** A tier-2 branch cannot be pushed or opened as a PR until a spec linked to it
(`branch:`) passes the gate and a panel is recorded, and the agent cannot merge it: enforced when
the pack hooks are on; otherwise held by discipline. You hold the line either way: at tier 2, do not
push, open a PR or merge until the spec exists, the three lenses ran and the user said yes to the
merge.

## 2. Spec gate (replaces `rsc spec gate`)

The gate checks the spec file, not the agent's confidence. Do it by hand on the written spec and
report PASS or FAIL per item.

1. The file is `02-DOCS/wiki/sdd/specs/<slug>.md` and has the frontmatter from
   `../../specify/references/spec-template.md`.
2. Every section of the template is present, with content or with an explicit typed open point.
   A heading with nothing under it, or only the template's guidance text, is empty. Required:
   Problem & why, Cost of not building it, The cheapest alternative, Goals, Non-goals / out of
   scope, Users & context, What the user can do, What result they get, What it must respect, How
   it proves it, Behaviour, Acceptance criteria, Points to clarify.
3. Each entry in Points to clarify carries one of the four types.
4. Each acceptance criterion is binary and observable.
5. If the work is on a branch, put `branch: <name>` in the frontmatter, so the spec can be linked
   to it. The pack's push hook finds the spec for the current branch by this line; without it a
   tier-2 push is blocked when the hooks are on.

Report in the form `FAIL <slug>: missing section(s): ...; empty section(s): ...`. A red result
means the spec is not closed. As in rsc, this does not catch an unmarked assumption; that part is
yours to find.

## 3. Review ledger (replaces `rsc review ledger`)

The ledger keeps the fix loop from running forever. Keep it by hand in
`02-DOCS/wiki/sdd/progress/<slug>.md`, under a `## Review rounds` heading, as an append-only list.

- **Round counter.** Before every review of a task, the first included, append a line
  `<task>: round N`. The 4th round is refused. Do not try harder: rethink the approach, or park
  the task in the decision queue as `blocking` and continue with independent work.
- **Findings.** Give each finding an id (`F1`, `F2`, ...) and record file, bug class and claim.
  A finding with the same file, class and meaning as an earlier one is a `repeat`: never raise it
  again, and say that the last fix missed the class.
- **Outcome.** When a finding closes, append its outcome: `fixed`, `false`, `intentional`,
  `irrelevant` or `parked` (its task went to the decision queue).
- **Panel record (tier 2).** After the three lenses ran, append
  `<task>: panel correctness, security, tests`, exactly so: the pack's push hook looks for this
  line (enforced when the pack hooks are on; otherwise held by discipline). Without it, a tier-2
  task is not reviewed.
- **Stats** are a count of the outcomes above, if the user wants the false rate.

## 4. Consolidating reports (replaces `rsc review consolidate`)

When several lenses or reviewers report, merge by hand before anything reaches the author:

1. Group findings that name the same place (same file, lines within about 10 of each other) and
   say the same thing, or that quote the same evidence. Keep the highest severity and list every
   lens that saw it. Several lenses on one finding is a reason to look first, never a reason to
   raise its severity.
2. Downgrade a `blocker` or `should-fix` that has no `file:line`, or no concrete failure scenario
   (input, then wrong result), to a `question`.
3. Every remaining blocker and should-fix is verified before it is reported (see the `review`
   skill, "Consolidate, then verify").
4. Report the count honestly: `11 reported, 4 unique, 2 confirmed`, and list what was refuted and
   why.

Each lens ends its report with a findings block in this shape, so grouping is mechanical:

```json
{"severity":"blocker|should-fix|nit|question","file":"path","line":N,"claim":"...","failure_scenario":"concrete input -> wrong result","evidence":"quoted code","class":"bug class"}
```

## 5. Escapes (replaces `rsc review escapes`)

List the reverts: `git log --grep='^Revert' --grep='^revert' -i --oneline`. For each one without a
case file at `02-DOCS/wiki/sdd/review-evals/<shortsha>.md`, write the case: the diff that shipped,
where the bug was, and what the reviewer should have said. A revert made by hand with another
message is not seen.

## 6. Where the work goes (replaces `rsc main status`, `rsc main unlock`, worktrees)

rsc records, per project, whether the default branch is open or closed to the agent. marcsh has no
such switch, so ask.

- Work that writes only docs, wiki or config needs no question.
- On the default branch (`main`, `master`), before the first code change of a feature ask in one
  line, with the question tool (`marcsh.md` §3): "Do it on this branch (`<current>`), on a new
  branch, or on `<default>` directly?" Recommend a new branch when the project has CI, a deployment
  or several people, and put it first. Wait for the answer and record it. (In
  paused AUTO or YOLO approval mode, recommend a worktree; see the agent's Approval mode rule.)
- Already on another branch: an unrelated change does not go into it without asking.
- Never switch the branch under another session working in the same folder. If you see signs of
  one (uncommitted changes you did not make, a lock file), say so and offer a separate worktree:
  `git worktree add ../<repo>-<branch> -b <branch>`. Do not create one otherwise.
- When the default branch is protected or the user says branches and PRs, a local merge to it is
  not offered at ship; offer the PR and the park option.

## 7. Registry, catalog and installs (replaces `registry refresh`, `catalog`, `add`)

The pack's skills are the ones listed in its README. There is no catalog and no installer to
suggest from. If a stack skill the text names (for example a FastAPI or Next.js skill) is not
loaded, say it is missing and carry on with the project's own commands and conventions. Never run
an install without the user asking.
