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
| `ansible-lint-version` | string  | `''`               | **Deprecated, ignored** (warning): ansible-lint comes from a hash-locked requirements file |
| `ansible-version`      | string  | `''`               | **Deprecated, ignored** (warning): ansible comes from a hash-locked requirements file |
| `python-version`       | string  | `'3.12'`           | Python version to use — **3.12 or newer** (the locked tools are resolved for it) |
| `fail-on-error`        | boolean | `true`             | Fail the job on lint violations; `false` runs in advisory mode (warnings)   |
| `run-syntax-check`     | boolean | `false`            | Run `ansible-playbook --syntax-check` on matching playbooks                 |
| `playbook-glob`        | string  | `'*.yml'`          | Glob (relative to `ansible-dir`) for playbooks to syntax-check              |
| `runner`               | string  | `'"ubuntu-latest"'`| Runner labels as JSON — `'"ubuntu-latest"'` or a label array                |

## Steps

1. Checkout
2. Setup Python
3. Install ansible-lint from its hash-locked requirements (`setup-ansible` action, `pip --require-hashes`)
4. Run ansible-lint over `ansible-dir` (advisory when `fail-on-error: false`)
5. _(if `run-syntax-check`)_ Install ansible the same way and run `ansible-playbook --syntax-check` on each playbook found

## Notes

- The `ansible-lint` job always runs; the `ansible-syntax-check` job runs only when `run-syntax-check: true`.
- The syntax check searches `ansible-dir` at depth 1 for files matching `playbook-glob`; if none are found it logs a warning instead of failing.
- Matching files that are not playbooks (no play declaring `hosts:` / `import_playbook:`, e.g. `requirements.yml`, `galaxy.yml`) are skipped rather than failing the syntax check.
- The tools are installed from `.github/actions/setup-ansible/{ansible-lint,ansible}.txt`, compiled with `uv pip compile --generate-hashes`: every package, direct and transitive, is checked against its SHA-256. Renovate bumps the pins and regenerates the locks; the version follows the release of this repository you pin.
