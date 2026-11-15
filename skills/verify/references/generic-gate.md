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
  `gh pr checks --watch`, dev servers and watchers.
  - On pi, start it with `bg_start`. Keep working on what does not depend on it; its exit status
    and the end of its output arrive by themselves, and `bg_status` shows them earlier. The full
    log path is in the result; read it when the end is not enough.
  - On Claude, use the engine's own background mode (the Bash tool's background option) and read
    the output when it has finished.
  - Where there is no background mode (Plan, `marcsh run`, a background subagent, which cannot
    start background terminals), give the call an explicit `timeout` above the expected run time.
    A command that sets its own `timeout` keeps it.
- **The exit code comes from the background result** (its `exited (…)` line, or `was killed`). A
  killed or timed-out run is recorded as not run, with the reason, and run again properly.
- **Runtime proof** (a page renders, an endpoint answers): `bg_start` the server, probe it in the
  foreground (`curl`, the project's own e2e command, with a short retry until it listens), record
  the probe's output, then `bg_kill` it. On Claude, start it in the background and stop it the
  same way. Never leave a server running when the check is done; background terminals also stop
  when the session closes. What else to stop and how to check: "Stop what you start" below.
- `bg_start` asks for approval exactly like `bash` for the same command, and the pack's hooks apply
  to it too. It gets no stdin: never start a command that waits for input.
- On an interactive pi session you may end the turn while background work runs: marcsh starts a
  turn with the result when it finishes. Never end it with a "shall I continue?".

## Stop what you start

A process a check starts and nobody stops (a dev server, a browser, a watcher, `cargo run`, a
`node` process) keeps using memory long after the proof is taken. marcsh marks every process its
tools start with `MARCSH_SESSION` and shows the live ones to you and to the user (`/ps`, and
`N leftover · /ps` in the status line); it stops nothing by itself.

- **Start them in the background.** Servers, browsers, watchers and `cargo run`/`node` processes
  go through `bg_start` on pi (the engine's background mode on Claude), never `cmd &` inside a
  foreground call.
- **Stop them once the proof is taken** (`bg_kill` on pi; on Claude, stop the background command
  with the engine's own tool), unless the user asked to keep them running.
- **Browsers (Playwright, Chrome).** Close the browser or context in the test code itself
  (`browser.close()` in a `finally` or `afterAll`), then check: a run that crashed leaves the
  browser and its helper processes behind.
- **Check before you close.** Before closing a task, a turn or a verification that ran processes,
  list the leftovers: `proc_list` on pi; on Claude `sh <verify skill dir>/scripts/leftovers` (the
  file is `../scripts/leftovers` from this one; `--count` prints only the number). Stop the ones
  this work started: `proc_stop` with their pids on pi, `sh <verify skill dir>/scripts/leftovers
  --stop <pid>...` on Claude. Never stop one you cannot tie to this work; ask the user instead.
- **Record it.** The evidence (the FTD feature document, the ASDD progress file, the verification
  record) says "no leftover processes", or names what was kept running and why.
- **Only this session's processes.** `proc_stop` takes only processes marked with this session;
  `leftovers --stop` re-checks the marker of each pid right before signalling it and refuses any
  other. If `proc_list` is not offered, use the script. If the script says `MARCSH_SESSION` is not
  set (a marcsh without leftover tracking), the check is **not run**: say so, and stop by hand only
  what you started yourself.
- **macOS hides some of them.** The system hides the environment of Apple's own binaries (`sh`,
  `sleep`) from the script, so it cannot see those; third-party programs such as `node` it can.

## Rules that still apply

- A `not run` layer whose surface exists fails the verdict, exactly like a SKIP in a stack script.
- A command the project wrote (a custom check script) is a home-grown gate: watch it fail and pass
  before trusting it.
- The generic gate is the verdict for this run, whatever else is available.
