# Ticket email: final hosted acceptance

October 18, 2026 · FEAT-069 · private operator checklist.

The connection setup is complete. GitHub [preview run 39117511031](https://github.com/tracyapps/EXP-design/actions/runs/39117511031)
passed through Vercel to the restricted Neon job role. Mail and retention remain
off. This checklist is preparation; it authorizes no sends, access grants or
deletions. The owner will push the remaining local commits.

## Live-test continuation, October 18

This later observation supersedes the initial paused-state paragraph above.
Owner has approved the controlled author/support recipient pair and completed
the secondary member's real email-code registration. Addresses are omitted here.
Fresh database preflight shows two accounts, the secondary author verified, one
intended verified support grant and zero tickets/mail jobs. The ordinary member
has no support-inbox link. No grants were added.

Fresh [preview run 39151277752](https://github.com/tracyapps/EXP-design/actions/runs/39151277752)
passes with 12 zero cleanup counts; mail/retention steps skipped. Production and
GitHub main remain at `72f7a4e`; unpushed commits affect tests/docs only.
For the approved test, Production Config flags `ACCOUNT_TICKETS_ENABLED` and
`ACCOUNT_TICKET_MAIL_ENABLED` were saved as `true`. Redeployment
`dpl_3s6rgoTz9RHJCaog3bpR4rSbpVWu` is READY at that same SHA. GitHub repository
mail/retention flags remain `false`, readiness `true`: manual delivery only.

Brave then blocked the EXP reload because an extension UI was open. Owner was
asked to dismiss it. The enabled form has not yet been read, no ticket created
and no `mail` operation invoked. Resume with the ordinary-member session, then
review the exact queued recipients before sending. The acceptance table below
is still pending; account creation/preview do not establish notification delivery.
Local sanitized preflight: `output/a11y/hosted-job-setup-20261018/live-ticket-inbox-preflight.json`.

## What is ready

- Account/auth, ticket queue, HTTP worker and pinned GitHub workflow are implemented.
- The dedicated job credentials work; database and mail-provider credentials stay
  in Vercel. GitHub receives only the dedicated job token.
- `npm run test:accounts` includes the combined loopback HTTP rehearsal in
  `tests/account-ticket-journey.test.mjs`: real email-code auth and cookies,
  separate restricted app/worker roles, ticket → staff notice → reply → member
  notice, opt-out/no replay, revoked access, duplicate suppression, local ticket
  deletion and sign-out. Provider requests are captured locally, never delivered.
- Existing fixtures cover ambiguous provider/DB acknowledgement, backoff, expiry,
  concurrent leases, retention boundaries and paused/unauthorized operations.

## Before a real email test

Owner/operator and Codex review these together after the push:

1. Confirm the pushed commit and production deployment are READY. Run `preview`
   again and save its aggregate receipt. No password setup or migration replay.
2. Identify two verified accounts controlled by the owner: one ordinary ticket
   author and the existing support operator. Explicitly approve the exact recipient
   addresses for test service mail; keep that list outside this public repository.
   The sending address is separate from the operator's account identity.
3. Inspect the current support grants and pending queue privately. Every eligible
   support member can receive a new-ticket notification. The flags are global,
   **not a private tester allowlist**. Stop if any recipient is outside the approved
   test group or if unknown pending work exists. Do not add grants or flush a queue
   simply to make the test possible.
4. Confirm `SIGNUP_FROM_EMAIL` is the intended verified Resend sender and support
   coverage is available. Never paste the API key, URLs, codes or cookies into chat.
5. Keep GitHub repository `ACCOUNT_TICKET_MAIL_ENABLED=false` and
   `ACCOUNT_RETENTION_ENABLED=false`; keep Vercel retention false. Then, only for
   the approved test, enable Vercel `ACCOUNT_TICKETS_ENABLED` and
   `ACCOUNT_TICKET_MAIL_ENABLED` and deploy. This enables ticket writes/queueing;
   delivery is manually dispatched while its GitHub schedule remains paused.

## Record the inbox journey

Use separate browser profiles/sessions for author and support, with disposable
test text such as “EXP notification acceptance test.” Never use private artwork
or an actual customer issue as test content.

| Action | Required observation | Hosted receipt |
| --- | --- | --- |
| Author creates one ticket | Exactly one thread/event; only eligible approved support recipients queued | Pending |
| Dispatch `preview`, then `mail` once | Aggregate counts match the approved queued events; no private content in Actions output | Pending |
| Operator checks inbox and spam | One service notice; correct sender and support link; no ticket text, name, code or login token | Pending |
| Open link while signed out | Sign-in required; support inbox available only with the existing grant | Pending |
| Operator replies on website | Author sees the reply; exactly one author notification queued | Pending |
| Dispatch `mail`; author checks inbox/spam | One reply notice; link opens the author's thread after sign-in | Pending |
| Repeat `mail` with no new events | Zero accepted; no duplicate mail arrives | Pending |
| Author turns ticket alerts off; operator replies | Reply visible on website, no author notice queued/delivered; news/beta/Pro choices unchanged | Pending |
| Author turns alerts on again | No old notice replayed; a new support reply generates one new notice | Pending |
| Author closes the test thread | Closed state persists after reload; no status-only email | Pending |

Use the reviewed workflow, not an ad hoc curl command with a token:

```sh
gh workflow run account-jobs.yml --repo tracyapps/EXP-design --ref main -f operation=preview
# Only after the recipient/queue review above and explicit test-send approval:
gh workflow run account-jobs.yml --repo tracyapps/EXP-design --ref main -f operation=mail
```

Record run links, deployment/commit, UTC timestamps, aggregate counts and owner
inbox/spam observations. Do not commit addresses, thread IDs, message bodies,
provider receipts or screenshots containing private inbox content. A provider
`accepted` count is not proof that mail reached the inbox.

## Finish or pause

- After a failed or incomplete test, pause Vercel ticket-mail queueing/sending and
  redeploy; keep the GitHub mail schedule off. Do not reset attempts, IDs or
  terminal states to force a resend. Leave existing threads readable.
- After all inbox checks pass, owner decides whether to keep ticket writes open
  and enable GitHub repository `ACCOUNT_TICKET_MAIL_ENABLED=true`. Confirm a real
  scheduled run and failure-notification coverage before relying on it. Scheduling
  is best effort; it is not a five-minute delivery promise.
- Hosted cross-user denial, grant revocation, account deletion and ticket erasure
  still need separately approved disposable identities/data. Do not revoke the
  sole real support operator or delete the owner's live account to test a gate.
  The local rehearsal proves these controls only in its isolated environment.
- Cleanup remains independently off until the owner approves the proposed policy,
  provider log/backup periods and restore-erasure procedure. No retention operation
  belongs in this inbox test.

Rollback, exact flags, policy proposal and historical receipts:
[ticket jobs handoff](TICKET-NOTIFICATIONS-AND-RETENTION-v2.7.md).
