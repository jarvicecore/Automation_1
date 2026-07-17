# ADR 0003: Reusable workflows and a composite action for shared CI logic

## Status

Accepted

## Context

`ci.yml` needs to run the same lint → type-check → test sequence against
three Python versions. Copy-pasting that sequence into three jobs (or a
matrix job that hand-duplicates the same steps `security.yml` also needs)
means every future change to the sequence — a new check, a changed cache
key, a renamed step — has to be made in every copy, and it's easy to miss
one. At the scale of an org with many repos, this duplication compounds:
the same five-step block ends up hand-copied across dozens of workflow
files, each drifting slightly from the others.

## Decision

- `.github/actions/setup-python-env/action.yml` is a **composite action**
  wrapping "install Python with pip caching, install the project in
  editable mode" — the two steps every job in this repo needs before it can
  run anything.
- `.github/workflows/reusable-python-tests.yml` is a **reusable workflow**
  (`workflow_call`) wrapping the full lint/type/test sequence. `ci.yml`
  calls it once per matrix entry via `uses:` rather than inlining the steps.

The dividing line: a composite action shares *steps within a job*; a
reusable workflow shares *whole jobs*, including their own permissions and
runner selection. `setup-python-env` is a composite action because it's a
setup fragment other jobs build on top of. The test sequence is a reusable
workflow because it's a complete, self-contained unit of work with its own
`permissions:` block.

## Consequences

- A new check (e.g. adding `pytest --doctest-modules`) is a one-line change
  in `reusable-python-tests.yml` that immediately applies to every Python
  version in the matrix, with no risk of updating 2 out of 3 copies.
- `ci.yml` itself stays short enough to read as an overview of *what* runs,
  with *how* it runs pushed down into the reusable workflow — useful when
  this pattern scales to an org-wide `.github` repository that many other
  repos call into, which is the natural next step for this template.
- Debugging is one hop further away: a failure in the matrix shows up
  inside the reusable workflow's own job page, not inline in `ci.yml`'s
  run. Worth it once the same logic is used from more than one place;
  not worth it for a one-off job.
