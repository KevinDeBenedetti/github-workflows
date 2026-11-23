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

### Downloaded tools

**Pinned tool**:
A program an action downloads at one fixed version and installs only after the download matches the SHA-256, or the commit, recorded with that version.
_Avoid_: dependency, binary

**Tool manifest**:
The file that lists every pinned tool with its version, its download and its pins. It is the only place a pin lives; the install reads it at run time.
_Avoid_: tool list, lockfile

### Dependency updates

**Shared preset**:
The Renovate config every repository that uses these workflows extends, `renovate/default.json`: the schedule, the release age, the SHA-pinned actions. A consumer pins it to a release, and release propagation moves that tag with its workflow pins.
_Avoid_: base config, shared config, Renovate template
