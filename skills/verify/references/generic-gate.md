# Generic gate — when no stack skill ships `scripts/verify.sh`

A project in a stack with no ready-made gate (a plain Node CLI, a Rust crate, a shell tool, and in
this pack any stack) is still verified. The gate is the commands the project itself declares.
This is a first-class path, not a fallback to apologise for.

## Where the commands come from

If the user has `02-DOCS/wiki/sdd/config.yaml`, use its `testing.commands.verify` (and
`testing.commands.apply` for the suite). Without it, read the manifests (`package.json` scripts,
`Makefile`, `Cargo.toml`, `pyproject.toml`…) and the CI configuration; do not pick commands from
memory, and say where each command came from.

## The five layers

| Layer | What counts | Typical source |
| --- | --- | --- |
| test | the full suite | `npm test`, `cargo test`, `pytest` |
| lint | the project's linter | `npm run lint`, `cargo clippy` |
| type | the type checker | `tsc --noEmit`, `mypy` |
| build | the build or compile | `npm run build`, `cargo build` |
| audit | dependency vulnerabilities | `npm audit`, `cargo audit`, `pip-audit` |

## Procedure

1. List the five layers. For each, take the command from `config.yaml` if there is one; if it
   declares none, look for one in the manifest or CI and say where you found it.
2. Run each command once, after the last edit, from the project root, by the long-command rule
   below. Capture the exit code and the relevant output verbatim: for a command run in the
   background, both come from its background result, never from a foreground call that timed out.
3. Record every layer as exactly one of:
   - **pass** — the command ran and exited 0;
   - **fail** — the command ran and exited non-zero (a hard FAIL of the verdict);
   - **not run** — no command is declared or the tool is missing. Label it as `verify` does:
     `NO-APLICA` (no such surface, e.g. no types in plain JS), `HERRAMIENTA-AUSENTE` (the surface
     exists, nothing checked it).
4. Write the layers under `## Stack gate` in the record, as `generic gate → …`, one line per
   layer, with the command that ran.

## Long commands

This is the one rule for how long commands run in this pack; every skill that runs a suite, a
build, an audit, a bisect, a CI watch or a server points here.

On pi, marcsh stops a foreground command (`bash`) or a foreground subagent (`Task`) after 3
minutes and hands the model a timeout error. A timed-out call is not a result: the check is
**not run**, never pass and never fail, until it runs to its end.

- **Foreground:** the focused RED and GREEN runs (one test file or one test), a single-file lint,
  quick git commands. Anything that reliably ends well inside 3 minutes.
- **Background, or an explicit `timeout`:** the full or affected suite, builds, type-checks of a
  large project, audits, `scripts/verify.sh`, flake loops (`k/N` runs), `git bisect run`,
  `gh pr checks --watch`.
  - On pi, start it with `bg_start`. Keep working on what does not depend on it; its exit status
    and the end of its output arrive by themselves, and `bg_status` shows them earlier. The full
    log path is in the result; read it when the end is not enough.
  - On Claude, use the engine's own background mode (the Bash tool's background option) and read
    the output when it has finished.
  - Where there is no background mode (headless `marcsh run`, a background subagent, which cannot
    start background terminals), give the call an explicit `timeout` above the expected run time.
    A command that sets its own `timeout` keeps it.
- **Servers and watchers: background only.** They never exit, so a `timeout` does not fit them,
  and `cmd &` inside a foreground call is never used. Where there is no background mode, do not
  start one: record the runtime proof it was for as **not run**, with the reason.
- **Plan runs no commands**, so none of this applies there.
- **Subagents.** `Task` has no timeout parameter: the 3-minute rule for subagents is in
  `../../asdd/references/marcsh.md` §2.
- **The exit code comes from the background result** (its `exited (…)` line, or `was killed`). A
  killed or timed-out run is recorded as not run, with the reason, and run again properly.
- **Runtime proof** (a page renders, an endpoint answers): start the server in the background
  (`bg_start` on pi, the Bash tool's background option on Claude), probe it in the foreground
  (`curl`, the project's own e2e command, with a short retry until it listens), record the probe's
  output, then stop it (`bg_kill` on pi; on Claude, the engine's own tool for stopping a background
  shell). Never leave a server running when the check is done; background terminals also stop when
  the session closes. Leftovers: "Stop what you start" below.
- `bg_start` asks for approval exactly like `bash` for the same command, and the pack's hooks apply
  to it too. It gets no stdin: never start a command that waits for input.
- On an interactive pi session you may end the turn while background work runs: marcsh starts a
  turn with the result when it finishes. Never end it with a "shall I continue?".

## Stop what you start

The rule is in `../../asdd/references/marcsh.md` §7. In short: servers, browsers and watchers
start only in the background and stop once the proof is taken; before closing a task, a turn or a
verification that ran processes, list the leftovers (`proc_list` on pi, otherwise
`sh <verify skill dir>/scripts/leftovers`, which is `../scripts/leftovers` from this file); never
stop one without the user's yes; the record says "no leftover processes" or what still runs and
why.

## Rules that still apply

- A `not run` layer whose surface exists fails the verdict, exactly like a SKIP in a stack script.
- A command the project wrote (a custom check script) is a home-grown gate: watch it fail and pass
  before trusting it.
- The generic gate is the verdict for this run, whatever else is available.
