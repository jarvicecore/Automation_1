# ADR 0004: The build must be bit-for-bit reproducible

## Status

Accepted

## Context

The entire promotion model (see [ADR 0001](0001-binary-promotion-over-rebuild-per-environment.md))
rests on a digest computed once, at build time, being a stable, permanent
identity for an artifact. If the same commit could produce different bytes
on different runs, that digest would stop meaning "this exact artifact"
and start meaning "an artifact roughly like this one" — which is precisely
the ambiguity binary promotion exists to remove.

Two independent sources of nondeterminism showed up in practice:

1. An early version of `scripts/build.sh` stamped `BUILDINFO` with
   `date`'s wall-clock output, so two builds of the identical commit,
   seconds apart, produced different bytes.
2. `tar`'s own metadata (mtime, ownership, entry order) was already
   pinned, but `tar -czf`'s built-in `-z` pipes through a `gzip` that
   embeds its own header timestamp — an independent source of
   nondeterminism sitting one layer below the one that had already been
   fixed.

## Decision

`scripts/build.sh` derives `built_at` from the **commit's** timestamp
(`git log -1 --format=%cI`), never the wall clock. The tarball is built
with `tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0
--numeric-owner`, piped through `gzip -n` explicitly (rather than tar's
built-in `-z`) so the compressed output carries no embedded timestamp
either.

## Consequences

- Verified directly: building the same commit twice, with a real wall-clock
  gap in between, produces byte-identical tarballs (same SHA256). This is
  a testable property, not an assumption — worth re-checking after any
  change to `build.sh`.
- Anyone extending `build.sh` inherits a contract, not just a script:
  nothing in the build path may read the wall clock, hostname, process ID,
  or any other run-specific value. `bash -n` and unit tests won't catch a
  regression here; only re-running the build twice and diffing digests
  will.
- This is the single easiest way to quietly hollow the whole system out —
  a nondeterministic build makes every digest check downstream (promote,
  deploy, the service's own self-verification) pass on essentially
  meaningless comparisons instead of real ones. It fails loudly (digest
  mismatch) rather than silently, but only because the rest of the system
  assumes this ADR holds.
