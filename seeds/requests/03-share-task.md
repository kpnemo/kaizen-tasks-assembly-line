---
title: Share a task with a teammate
---

### Problem

Half of my tasks are really joint tasks with one teammate. Today we each keep a copy and they drift apart within a day; last week we both did the same step. There is no way to see a task someone else owns.

### Proposed behavior

On the task detail page, a "Share" control where I type a teammate's email. When they log in, the task appears in their list with a "shared by <name>" badge. Both of us can check steps, edit titles, and accept suggestions, and both see the other's changes on the next poll.

### Acceptance criteria

- The owner can share a task with another registered user by email from the task detail page.
- The shared task appears in the other user's task list with a "shared by <display name>" badge and opens in their task detail.
- Both users can change step status, edit step titles, and accept or dismiss suggestions; a change by one is visible to the other within five seconds.
- Sharing with an unknown email shows the error "No user with that email".
- The owner can unshare; the task then disappears from the other user's list.
- Tags remain the owner's; the other user sees them but cannot edit them.

### Out of scope

- Sharing with more than one person.
- Comments or activity history.
- Notifications by email.

### Your role

Product lead, workforce management
