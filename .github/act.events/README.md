# act.events fixtures

This folder contains sanitized workflow_dispatch event payloads (JSON) used for local runs with `act`.

- Purpose: allow reproducible local executions of selected workflows without networked triggers.
- Safety: do not include tokens or secrets; keep inputs minimal and generic (e.g., empty `ci_image_tag`).
- CI impact: these files are data-only; they do not affect GitHub Actions in hosted CI.

Conventions:

- One `*-event.json` per workflow that we run via `act workflow_dispatch`.
- Minimal shape:
  {
  "event_name": "workflow_dispatch",
  "ref": "refs/heads/main",
  "inputs": { "ci_image_tag": "" }
  }

If a workflow adds new inputs, update the corresponding `*-event.json` with safe defaults.
