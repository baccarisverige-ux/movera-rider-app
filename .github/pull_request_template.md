## Change

What changes and why (one paragraph; name the owner decision or plan step it comes from).

## Proof (Rule 36 / 45)

- Failing test before → passing after (file and test name):
- Counts (tests run / passed; files and line counts for split work):
- Screenshots for every visible change:

## NOT checked

What this PR does not prove (platforms, flows, data) and why.

## Rule 0

Which of the five parts change: contract / server / admin (incl. setting) / driver / rider.
For each part not changed: "no change needed" and the reason.

Fill every row of the table (the check "Rule 0: all 5 parts" fails otherwise). Status = a PR (`#123` or `owner/repo#123`), `this PR`, or `not affected` plus a `file:line` proof (for example `src/app.ts:42`). An empty cell, TBD or a question mark fails. Docs-only changes fill it too.

| Part | Status | Notes |
|---|---|---|
| Contract |  |  |
| Server |  |  |
| Admin (incl. setting) |  |  |
| Driver |  |  |
| Rider |  |  |

## Checklist

- [ ] Contract first: `contracts/` is synced from a merged, tagged contract version, never edited by hand (Rule 43(4)).
- [ ] Supervisor check before and after the merge (Rule 45).
- [ ] Every touched hand-written file is under 1,500 lines (Rule 25).
- [ ] No secrets, codes, phone numbers or e-mail addresses in the text.
