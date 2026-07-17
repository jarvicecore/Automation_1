# Use cases

Five situations this pipeline is built to handle, told from the perspective
of the person living through them. For the mechanics behind each, see
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md); for the exact commands, see
[`docs/WALKTHROUGH.md`](WALKTHROUGH.md).

## Shipping a routine change

**You're a developer.** You've made a change to the extract logic, opened a
PR, and now you want it in front of real users without personally
babysitting six deployments.

You open the PR. `ci.yml` builds it, runs `test.sh`, and runs the full
security gate — CodeQL, dependency review, `reposentry`, and whatever
commercial scanners are enabled — against your branch. Nothing you do here
can publish anything; `ci.yml` calls `_build.yml` with `publish: false`, so
even a successful CI run produces no attestation and no release. You get a
single required check, `ci-passed`, so you don't need to know which of the
dozen underlying jobs matter this week — if any of them genuinely failed,
that one check tells you.

You merge. `release.yml` picks it up, builds the artifact **exactly once**,
attests its SLSA provenance, publishes it as a GitHub Release, and
auto-deploys it to `dev`. You didn't ask for `dev` to be updated — it always
is, because `dev` runs whatever the latest release is, by definition (see
[ADR 0003](adr/0003-dev-has-no-manifest-file.md)).

**What you did not just do:** touch Prod, QA, or anything a customer or
tester relies on. Your change exists as a released, attested artifact and is
live in exactly one place. Everything past `dev` is a separate, deliberate
decision — see the next scenario.

## Promoting a release through environments

**You're a release manager.** QA has signed off on `v0.1.42`, currently
running in the `qa` environment, and it's time to move it to `stage`.

You go to Actions → Promote → Run workflow, pick `stage` as the target, and
give a change reference — required, because it's what lands in the
promotion PR as the audit trail. The workflow:

1. Resolves `stage`'s source (`qa`, per
   [`promotion-path.yaml`](../environments/promotion-path.yaml)).
2. Downloads `qa`'s currently-approved release asset and re-hashes it,
   confirming nobody's touched it since `qa` signed off.
3. Verifies its SLSA provenance back to `_build.yml`.
4. Opens a PR that changes exactly one line: `environments/stage.yaml`'s
   `release_tag`.

You didn't deploy anything yet. The PR sits there — a diff of
`v0.1.41 → v0.1.42`, a digest, a reason — until whoever
[`CODEOWNERS`](../.github/CODEOWNERS) names for `stage` approves it. In an
enterprise configuration that's `@qa` and `@release-managers` both; in the
solo configuration this repo currently runs in, it's you, clicking a real
approval gate rather than being waved through (see
[ADR 0008](adr/0008-solo-mode-vs-enterprise-codeowners.md)).

Merging the PR is what actually moves bits: `deploy.yml` notices
`stage.yaml` changed, and `_deploy.yml` re-verifies the digest and
provenance **again**, independently of the checks `promote.yml` already ran,
before installing anything (see
[the three-gate model](ARCHITECTURE.md#the-three-gate-verification-model)).

You cannot promote `qa` straight to `prod` — the workflow only offers
targets reachable along `promotion-path.yaml`, and `stage`, `uat` are in the
way on purpose. You also cannot open a promotion PR that changes nothing:
if `stage` already runs `v0.1.42`, the workflow refuses before opening a PR,
so nobody's asked to review an empty diff.

## An emergency rollback

**You're on call.** `v0.1.42` is in Prod and something is wrong — a
regression only visible under production load. You need the previous
release back, now, without waiting for a fresh build (which, per
[ADR 0001](adr/0001-binary-promotion-over-rebuild-per-environment.md), you
never do anyway) and without inventing a rollback procedure under pressure.

You don't need one. `environments/prod.yaml`'s git history **is** the
record of every release Prod has run. Rollback is:

```bash
git log environments/prod.yaml            # find the previous release_tag
git revert <the promotion PR's merge commit>
```

That reverts `release_tag` and `artifact_sha256` back to the prior,
already-verified values. Opening that as a PR and merging it triggers
`deploy.yml` exactly the way any promotion does — same digest check, same
provenance check, same smoke test. **Rollback is not a special path.** It's
the same deploy mechanism every promotion already uses, pointed backward,
which is precisely why it's trustworthy under pressure: it's been exercised
every time someone promoted forward.

## Detecting a tampered deployment

**You're validating the tamper-detection story** — either because you're
evaluating this pipeline, or because something in Prod looks wrong and you
need to know whether the running bytes are actually what was promoted.

Every deployed service answers this itself. `GET /version` returns the
release tag, the digest the promotion recorded (`expected_sha256`), and the
digest the service just computed from the artifact actually on disk
(`observed_sha256`). If they match, `self_verified: true` and HTTP `200`.
If they don't — or if either value is missing — it's `self_verified: false`
and HTTP `409`, deliberately: "unknown" never counts as verified (see
[`src/app/provenance.py`](../src/app/provenance.py)).

You can force this state on purpose, locally:

```bash
docker exec -u root automation1-prod sh -c 'echo tampered >> /opt/app/artifact.tar.gz'
docker restart automation1-prod
curl -s http://localhost:8085/version   # self_verified: false, HTTP 409
```

The same tampered artifact also fails `smoke-test.sh`, which is what a real
deploy runs immediately after installing bits — so in the live pipeline,
this state gets caught and fails the deploy before anyone's paged, not
after. See [`docs/WALKTHROUGH.md`](WALKTHROUGH.md#break-it-on-purpose) for
the full sequence including restoring it afterward.

## Monitoring drift

**You're a platform owner** trying to answer a question that's easy to lose
track of across six environments: how far behind Prod is Dev right now, and
is anyone actually using the promotion process, or has it quietly turned
into a formality people route around?

[`scheduled-security.yml`](../.github/workflows/scheduled-security.yml)
runs nightly and, alongside a full security re-scan and OpenSSF Scorecard,
prints a drift table to the job summary: every environment, the release
tag it's running, and when it was last promoted. A large gap between what
`dev` is on and what `prod` is on isn't itself a problem — but a gap that
only ever grows is an early signal that the promotion process is being
bypassed under pressure rather than used, which is worth knowing before an
incident forces the question, not during one.
