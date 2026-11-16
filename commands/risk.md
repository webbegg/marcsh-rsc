---
description: Compute the risk tier of the current diff
agent: ftd
argument-hint: "[base branch]"
---

Base (empty means the default branch): $ARGUMENTS

Compute the risk tier of the change against that base by hand, with the path table and content
signals in `asdd/references/without-rsc-cli.md` section 1: the paths from
`git diff --name-only --no-renames <base>...HEAD` plus uncommitted and untracked files, then the
added lines. State the tier in one line with the reason, the classes touched, the reviewers it
needs (0, 1 or 3) and whether a human must approve the merge. Change nothing.
