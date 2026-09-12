Review a specification before it is built. Issue #<n> in kpnemo/kaizen-tasks-assembly-line, "<title>". Read only, change nothing.

Read, in this order:
1. `<spec path>` — the specification under review.
2. `<briefing path>` — what the agent knew about the product and the code before it wrote the spec, with the assumptions it took under "## Assumptions".
3. `<issue body path>` — the request as filed, every comment included; a later comment overrides an earlier one.

Judge the spec against the request and the briefing, not against your own preferences. Challenge every assumption the issue does not support. Look for: an acceptance criterion the spec restates differently from the issue; behavior the spec invents that nobody asked for; a criterion that is not testable as written; a place where "What exists today" contradicts what the spec says it will change; a missing failure path a user would hit on the first day.

Never ask a question back and never hedge with "it depends": when information is missing, name the gap under Must fix with the change that closes it. Reply in under 80 lines, in exactly this shape and nothing else:

Verdict: <sound | sound with changes | unsound>

## Must fix
- <spec section> — <the change, one or two sentences>

## Should fix
- <spec section> — <the change, one sentence>

An empty list is the single word "none" under its heading.
