# Issue tracker: Local Markdown

Issues and specs for this repo live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- The spec is `.scratch/<feature-slug>/<feature-slug>-spec.md`.
- Implementation tickets use one file per ticket:
  `.scratch/<feature-slug>/issues/<NN>-<slug>.md`.
  Number from `01` in dependency order, with blockers first.
- Record triage state as a `Status:` line near the top of each issue file.
  Use the role strings in [triage-labels.md](triage-labels.md).
- Append comments and conversation history under `## Comments`.

## When a skill says "publish to the issue tracker"

Create the appropriate spec or issue file at the paths above, creating
directories as needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. Ticket numbers are scoped to their
feature directory; resolve a number within the relevant feature.

## Wayfinding operations

Used by `/wayfinder`. The map is a file with one child file per ticket.
Wayfinder uses `claimed` and `resolved` as its workflow states.

- **Map**: `.scratch/<effort>/map.md`, containing Notes,
  Decisions-so-far, and Fog.
- **Child ticket**: `.scratch/<effort>/issues/<NN>-<slug>.md`,
  numbered from `01`, with the question in the body.
  A `Type:` line records `research`, `prototype`, `grilling`, or `task`.
  A `Status:` line records the workflow state.
- **Blocking**: a `Blocked by: NN, NN` line near the top.
  A ticket is unblocked when every listed ticket is `resolved`.
- **Frontier**: scan the effort's issues for unresolved, unblocked,
  unclaimed tickets; first by number wins.
- **Claim**: set `Status: claimed` and save before beginning work.
- **Resolve**: append the answer under `## Answer`, set `Status: resolved`,
  then append a context pointer (gist and link) to Decisions-so-far
  in `map.md`.
