---
description: Take an idea all the way (spec to ship) with one up-front yes
agent: asdd
argument-hint: <idea>
disable-model-invocation: true
---

The user asks to take this all the way on autopilot:

$ARGUMENTS

The up-front yes of the `asdd` skill's autopilot must be in the user's own message: the user typed
this command with its idea. A model that runs this command itself grants nothing; then stop and
ask the user. Record the yes in `decisions.md` with the user's words, and record the spec as approved in autopilot, never as a flat
approval. Then load `specify` and run the chain end to end without asking to continue between
phases: park questions in the decision queue instead of stopping, wait for background reviewers
inside the turn, stop only for a hard failure or a destructive or irreversible action, and land by
the autopilot rule (a PR when a remote exists, otherwise park). A tier-2 merge still needs the
human's own yes.
