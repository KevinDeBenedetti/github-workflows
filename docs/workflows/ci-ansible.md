# CI — Ansible

Runs **ansible-lint** and an optional **syntax check** over a directory of Ansible playbooks/roles.
Installs Ansible tooling via pip on the selected Python version.

## Usage

```yaml
jobs:
  ci:
    uses: KevinDeBenedetti/github-workflows/.github/workflows/ci-ansible.yml@main
    with:
      ansible-dir: ansible/
      run-syntax-check: true
```

## Inputs

| Input                  | Type    | Default            | Description                                                                 |
| ---------------------- | ------- | ------------------ | --------------------------------------------------------------------------- |
| `ansible-dir`          | string  | `ansible/`         | Directory containing Ansible playbooks/roles                                |
| `ansible-lint-version` | string  | `''`               | ansible-lint version to install (pip specifier, e.g. `>=25.0,<26`)          |
| `python-version`       | string  | `'3.12'`           | Python version to use                                                       |
| `fail-on-error`        | boolean | `true`             | Fail the job on lint violations; `false` runs in advisory mode (warnings)   |
| `run-syntax-check`     | boolean | `false`            | Run `ansible-playbook --syntax-check` on matching playbooks                 |
| `playbook-glob`        | string  | `'*.yml'`          | Glob (relative to `ansible-dir`) for playbooks to syntax-check              |
| `runner`               | string  | `'"ubuntu-latest"'`| Runner labels as JSON — `'"ubuntu-latest"'` or a label array                |

## Steps

1. Checkout
2. Setup Python
3. Install ansible-lint (with `ansible-lint-version` specifier when set)
4. Run ansible-lint over `ansible-dir` (advisory when `fail-on-error: false`)
5. _(if `run-syntax-check`)_ Install ansible and run `ansible-playbook --syntax-check` on each playbook found

## Notes

- The `ansible-lint` job always runs; the `ansible-syntax-check` job runs only when `run-syntax-check: true`.
- The syntax check searches `ansible-dir` at depth 1 for files matching `playbook-glob`; if none are found it logs a warning instead of failing.
- `ansible-lint-version` is a raw pip version specifier appended to the package name (e.g. `ansible-lint>=25.0,<26`).
