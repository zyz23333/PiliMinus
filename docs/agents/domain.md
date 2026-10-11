# Domain Docs

Use a single-context layout for this repo.

## Before exploring the codebase

- Read `CONTEXT.md` at the repo root.
- Read ADRs under `docs/adr/` that concern the area being explored.

If these documents do not exist, proceed silently.
The `/domain-modeling` skill creates them lazily when domain terms
or architecture decisions are resolved.

## File structure

All paths below are relative to the repo root.

- `CONTEXT.md`: domain vocabulary and model.
- `docs/adr/`: architecture decision records.
- `lib/`: application source.

## Use the glossary's vocabulary

Use the terms defined in `CONTEXT.md` when naming domain concepts in
issues, refactor proposals, hypotheses, and tests.

If a needed concept is absent, reconsider whether it matches the
project's language or note the gap for `/domain-modeling`.

## Flag ADR conflicts

Explicitly identify any existing ADR that a proposal contradicts,
and explain why the decision should be reopened.
