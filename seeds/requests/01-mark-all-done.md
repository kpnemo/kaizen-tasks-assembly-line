---
title: Add a "Mark all steps done" button on the task detail
---

### Problem

When I finish a task that has five or six steps I tick each checkbox one by one. On a laptop in a meeting that is five clicks and five list re-renders for one outcome. I do this several times a day, and two colleagues in the pilot asked for the same thing.

### Proposed behavior

On the task detail page, in the bulk bar, a button labeled "Mark all steps done". Clicking it sets every accepted or user-created step to done and the progress label updates to `N/N`. Suggested and dismissed steps are left as they are. No API change is needed: the web app updates each counted step through the existing update endpoint.

### Acceptance criteria

- On a task with at least one accepted or user-created step that is not done, the task detail shows a button labeled "Mark all steps done".
- Clicking it sets the status of every accepted or user-created step to done using the existing `PATCH /api/v1/tasks/:id` endpoint (one request per step is acceptable), and the progress label reads `N/N` where N is the number of those steps.
- Steps in the suggested or dismissed state keep their state and status.
- When every counted step is already done, the button is disabled.
- The web app has component tests for the happy path (three steps become done, label reads `3/3`) and for the disabled state; `CHANGELOG.md` has an `[Unreleased]` bullet.

### Out of scope

- Undo of the bulk action.
- Marking the parent task itself as done automatically.
- A keyboard shortcut.

### Your role

Product manager, contact-center analytics
