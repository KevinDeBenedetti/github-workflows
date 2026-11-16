# github-workflows

Reusable GitHub Actions workflows and composite actions that other repositories call to check, build, release and clean up their code.

## Language

### Change detection

**Change base**:
The commit a run's change starts from: what a check compares against to find the commits or files the run brings.
_Avoid_: commit range, base ref, diff base, before

**Fork point**:
The commit where a branch left the default branch. It stands in as the change base when a push's previous commit is gone, after a new branch or a force push.
_Avoid_: merge base

**Trusted commit**:
The commit whose secret-scan configuration and ignore list a scan applies. It is never among the commits under scan, so a change cannot silence its own findings.
_Avoid_: trusted ref, config ref
