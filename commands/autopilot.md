---
description: Take an idea all the way (spec to ship) with one up-front yes
agent: asdd
argument-hint: <idea>
---

The user asks to take this all the way on autopilot:

$ARGUMENTS

Running this command is the up-front yes of the `asdd` skill's autopilot. Record it in
`decisions.md` with these words, and record the spec as approved in autopilot, never as a flat
approval. Then load `specify` and run the chain end to end without asking to continue between
phases: park questions in the decision queue instead of stopping, wait for background reviewers
inside the turn, stop only for a hard failure or a destructive or irreversible action, and land by
the autopilot rule (a PR when a remote exists, otherwise park). A tier-2 merge still needs the
human's own yes.
