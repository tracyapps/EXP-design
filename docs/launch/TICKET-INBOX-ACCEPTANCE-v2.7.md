# Ticket email: final hosted acceptance

October 18, 2026 · FEAT-069 · private operator checklist.

The controlled live inbox test is complete. Author/support round trip, real inbox
delivery, signed-out and ordinary-member support-access denial, opt-out/no replay
and closure pass. Production ticket-write/mail flags are restored to `false`;
automatic mail and retention remain off. This checklist does not authorize new
sends, access grants or deletions. The owner will push remaining local commits.

## Verified result, October 18

- Support session opens the delivered link and saves a reply through the website.
  [Run 39158314830](https://github.com/tracyapps/EXP-design/actions/runs/39158314830)
  accepts one approved-author notice; owner confirms actual secondary inbox delivery.
- Fresh private window requires sign-in for the support link. The ordinary member
  then sees “Support access is not available for this account”; their own thread
  remains readable, including all support replies.
- Member saves alerts off. The next support reply is visible on the website, but
  DB shows zero pending jobs and no new mail row; [run 39158635277](https://github.com/tracyapps/EXP-design/actions/runs/39158635277)
  accepts zero. Saving alerts on leaves that suppressed event absent.
- A new support reply after opt-in creates exactly one approved-author job;
  [run 39158735878](https://github.com/tracyapps/EXP-design/actions/runs/39158735878)
  accepts one. Owner confirms **exactly two** secondary reply messages total:
  initial reply and new post-opt-in reply; none for the opted-out reply.
- Author closes the ticket; reload and DB agree: status closed, revision 5,
  five events, three accepted notification rows, zero pending, all three frozen
  envelopes cleared. Support grant count stays one. No status-only notification.
- Production Config `ACCOUNT_TICKETS_ENABLED=false` and
  `ACCOUNT_TICKET_MAIL_ENABLED=false` are saved and loaded by READY deployment
  `dpl_8sQuTepgenaJYkLBK4dSp5pcdEuY`, source `72f7a4e`. Both member and support
  reloads display paused delivery/writes and the closed thread.
  [Final preview 39159027869](https://github.com/tracyapps/EXP-design/actions/runs/39159027869)
  succeeds with 12 zero cleanup counts. Repository readiness true; scheduled
  mail/retention false. No cleanup or permanent deletion ran.
- Temporary private member session signed out and its window closed; original
  owner support session preserved. Both accounts and closed test thread retained.

Sanitized evidence: `output/a11y/hosted-job-setup-20261018/live-ticket-inbox-20261018.json`,
per-run result/log/aggregate files and `final-closed-ticket-paused.png`. Private
addresses, thread IDs and provider receipts are omitted from this repository.
The setup observations below are dated history, superseded by this final state.
Remaining rollout gates are listed under **Finish or pause**; this test does not
establish hosted account erasure, grant-revocation, retry-failure or physical AT proof.

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

Later native-control continuation: the extension-backed tab still reports a
block; native Brave accessibility shows no popup but a tabExtend footer alongside
EXP. Supported native controls successfully create one synthetic ticket. The
exact pending job/approved recipient is checked privately before dispatch.
[Mail run 39157768945](https://github.com/tracyapps/EXP-design/actions/runs/39157768945)
accepts one notice, with no retries/failures/skips. Gmail independently confirms
INBOX delivery (not SPAM), SPF/DKIM/DMARC pass, the correct support link and no
ticket text or login token. Sender is `hello@expdesign.app`. Duplicate-check
[run 39157987865](https://github.com/tracyapps/EXP-design/actions/runs/39157987865)
accepts zero; inbox search still shows exactly one notice. Owner support sign-in
is now pending private code entry before the reply test. Automatic mail/retention
remain off; Production test write/queueing flags remain on. Sanitized evidence:
`output/a11y/hosted-job-setup-20261018/live-ticket-inbox-20261018.json`.

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
| Author creates one ticket | Exactly one thread/event; only eligible approved support recipients queued | Pass Oct 18: real UI receipt and exact DB recipient/queue check |
| Dispatch `preview`, then `mail` once | Aggregate counts match the approved queued events; no private content in Actions output | Pass: preview 39151277752; mail 39157768945 accepted 1, other counts 0 |
| Operator checks inbox and spam | One service notice; correct sender and support link; no ticket text, name, code or login token | Pass: Gmail INBOX, not SPAM; headers/body verified through connector |
| Open link while signed out | Sign-in required; support inbox available only with the existing grant | Pass: fresh private sign-in gate and ordinary-member support denial |
| Operator replies on website | Author sees the reply; exactly one author notification queued | Pass: actual support/member UI plus exact DB event/recipient check |
| Dispatch `mail`; author checks inbox/spam | One reply notice; link opens the author's thread after sign-in | Pass: run 39158314830 accepted 1; owner confirms INBOX; own thread displays reply |
| Repeat `mail` with no new events | Zero accepted; no duplicate mail arrives | Pass for initial support notice: run 39157987865 all counts 0; inbox count remains 1 |
| Author turns ticket alerts off; operator replies | Reply visible on website, no author notice queued/delivered; news/beta/Pro choices unchanged | Pass: saved false; visible reply; unchanged 2 mail rows/zero pending; run 39158635277 accepted 0. Separate-purpose schema untouched by this operation |
| Author turns alerts on again | No old notice replayed; a new support reply generates one new notice | Pass: no row on opt-in; one new event/job; run 39158735878 accepted 1; owner confirms exactly 2 reply messages total |
| Author closes the test thread | Closed state persists after reload; no status-only email | Pass: closed/revision 5; 5 events; still only 3 accepted mail rows and zero pending |

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
- Hosted foreign-author isolation (a third ordinary account), grant revocation,
  account deletion and ticket erasure still need separately approved disposable
  identities/data. Do not revoke the
  sole real support operator or delete the owner's live account to test a gate.
  The local rehearsal proves these controls only in its isolated environment.
- Cleanup remains independently off until the owner approves the proposed policy,
  provider log/backup periods and restore-erasure procedure. No retention operation
  belongs in this inbox test.

Rollback, exact flags, policy proposal and historical receipts:
[ticket jobs handoff](TICKET-NOTIFICATIONS-AND-RETENTION-v2.7.md).
