---
description: Run the closing verification of a branch against main
agent: asdd
argument-hint: "[spec slug]"
---

Spec slug (empty means the feature on the current branch): $ARGUMENTS

Load the `verify` skill in closing mode: merge main in (or rebase), run the full gate by the
long-command rule (in the background, the exit code from the background result), walk every task
done-check and acceptance criterion, write the rollback plan, and record the dated verdict under
`02-DOCS/wiki/sdd/verifications/`. A check that did not run is "not run", never passed.
