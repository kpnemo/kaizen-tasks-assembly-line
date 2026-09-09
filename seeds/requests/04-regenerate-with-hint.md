---
title: Regenerate suggestions with a hint
---

### Problem

When the assistant's first breakdown misses the point, my only option is to regenerate blind and hope. For a task like "Prepare the QBR deck" I usually know what is missing ("the deck is for finance, not engineering") and I cannot say so. I regenerate two or three times a week and it rarely gets closer.

### Proposed behavior

The Regenerate button on the task detail opens a small text field, "Anything the assistant should know?", with a Regenerate button. The hint is sent with the regenerate request and passed to the assistant as part of the task input, next to the title and description. The system prompt and the output shape do not change. The hint is not stored on the task.

### Acceptance criteria

- On the task detail, Regenerate opens an optional single-line hint field (maximum 300 characters) and a Regenerate button; submitting with an empty hint behaves exactly like today.
- `POST /api/v1/tasks/:id/breakdown` accepts an optional JSON body `{ "hint": string }`; a hint longer than 300 characters returns `VALIDATION_ERROR` with the path `body.hint`.
- The hint reaches the breakdown model as a `hint` field of the task input; the API has a test that the fake model receives it.
- The task detail shows the thinking state after submitting and the new suggestions replace the previous suggested steps; accepted steps are kept.
- The API's `openapi.json` and the web's generated types include the new body; `CHANGELOG.md` in both repos has an `[Unreleased]` bullet.

### Out of scope

- Storing hint history on the task.
- Suggesting hints automatically.
- Changing the system prompt or the number of steps.

### Your role

Product manager, agent desktop
