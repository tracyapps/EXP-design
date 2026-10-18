# Ticket notifications and account cleanup

October 17, 2026 · FEAT-069 continuation. Implemented and tested locally. No hosted
migration, production setting, scheduler, live deletion or real mail send in this
slice. Production ticket writes remain paused. This extends
[news and private tickets](NEWS-AND-TICKETS-v2.7.md); its original no-notifier/no-job
statements describe the earlier slice, superseded locally here.

## Member and support behavior

- A new ticket or author reply queues a brief service notification to other
  currently granted, verified support members who have ticket alerts enabled.
  A support reply queues one to the verified ticket author. The actor is excluded.
  Status changes, sign-ins, old threads and permission changes do not trigger mail.
- My tickets and the support inbox have a **ticket email** choice, separate from
  news, beta, Pro and release permissions. Service alerts default on when the
  operator enables this feature; the member can turn them off even while delivery
  is paused. Turning off deletes pending recipient jobs; turning back on never
  backfills old events. Saving the choice does not send anything.
- Mail has a fixed subject and a ticket sign-in link. It includes no ticket
  subject/message, private name, artwork, attachment, login code or bearer token.
  A ticket UUID is a reference, not authorization: the session/ownership/staff
  checks still apply. Reply on the website; inbound email is not ticket ingestion.
- `ACCOUNT_TICKET_MAIL_ENABLED=false` defaults to no new queue entries and no
  worker delivery. Existing tickets and email preferences remain usable. The UI
  explicitly reports paused delivery. The native app and newsletter sender are
  outside this change.
- If code arrives before migration 009, paused existing ticket reads still work;
  the new choice stays hidden and attempts to save it return an unavailable
  response. A missing table is distinguished from a real privilege/storage error;
  those errors still fail closed. Apply migration/grants before enabling mail.

## Persistence, failures and deletion

Migration **009**, in the existing account DB after 003/005/007/008, adds:

| Table/change | Private data and lifecycle |
| --- | --- |
| `exp_member_ticket_preference` | Current email-alert choice, account UUID, timestamp; account erasure cascades |
| `exp_member_ticket_mail` | Random job ID, event/recipient references, audience, state/times/attempts/lease; event or recipient deletion cascades |
| First-attempt envelope | Recipient email, sender, fixed subject/text/sign-in link, frozen for retries; cleared on accepted/failed/skipped outcomes |
| Terminal receipt | Provider acceptance ID and generic outcome, without provider response/error text; 30-day cleanup proposal |
| Community `resolved_at` | Explicit operator review completion; unresolved reports never expire merely because they are old |

The ticket, event, write quota, audit and notification insert commit together.
Provider latency/failure is outside that transaction. Unique event/recipient keys
and the existing content-bound request receipts prevent repeat requests creating
duplicate jobs. There is no backfill on migration or feature enablement.

Workers claim bounded batches (20 jobs by default, maximum 100), using short
transactions, `FOR UPDATE SKIP LOCKED` and committed two-minute leases. They
freeze the envelope before any external request and use `exp-ticket/<job UUID>`
as the provider key. Each request has a five-second timeout. Network/ambiguous
responses, 429 and 5xx retry with exponential backoff (one minute through one
hour); permanent provider rejection stops. At most eight attempts. No retry
after 23 hours from first claim or seven days in the queue. Do not reset job IDs,
attempt clocks or terminal states to resend an ambiguous notification.

This deliberately stays inside Resend's documented **24-hour** idempotency
window, with the exact same payload for a key. A lost provider response or failed
DB acknowledgement recovers with that saved key/envelope. An accepted API receipt
is **not inbox delivery proof**; bounce/delivery webhooks and inbox/spam checks
remain future operating work. Invalid success receipts are treated as ambiguous.

Immediately before sending, recheck verified email, current email choice, ticket
existence, audience ownership/current staff grant, lease and retry window. A
changed recipient cancels rather than redirecting an already attempted envelope.
Revocation/deletion after the final check cannot recall an external request
already in flight. Account/ticket deletion removes queued jobs and local receipts;
sent mail, provider logs and backups are separate. No raw mail bodies, identifiers,
connection strings or provider errors are printed by the operator command.

## Proposed cleanup policy: `member-retention-v1`

These are implementation defaults for owner review, **not an enabled production
policy**. `ACCOUNT_RETENTION_ENABLED=false` and an explicit versioned command are
both required to change before live erasure can run. Update the version, copy and
checks if the retention periods change.

| Data | Proposed expiry |
| --- | --- |
| Sessions | After their authentication expiry |
| OTP/challenge rows | One day after expiry; never a live challenge |
| Authentication/mail/feature abuse counters | After one day of inactivity; current hourly protection remains |
| Closed tickets, all events, linked audit and mail jobs | 180 days since last ticket update; open tickets always retained |
| Private beta feedback | 365 days since submission |
| Community reports | 90 days after explicit operator resolution; unresolved reports retained |
| Standalone staff audit metadata | 180 days; thread deletion can remove it sooner |
| Terminal notification receipts | 30 days after completion |
| Never-attempted or abandoned pending notification jobs | Seven days from queueing, excluding a live lease |

Active accounts, private/public profiles, current purpose permissions, staff grants
and Pro connection references are not expired by this job. Their explicit
withdrawal/deletion paths remain available. The separate Pro/usage/release stores
are not touched. Beta feedback has no ongoing reply thread; tickets do.

Preview reports aggregate eligible counts and queue state counts only. Apply
uses atomic bounded statements, at most 500 direct rows per table per run
(configurable 1–1,000 in the private function), skipping rows locked by edits or
reopening. Cascaded child rows are additional to that direct-row bound. Counts
are per statement, not a frozen global snapshot. A job failure does not roll back
earlier successful table batches; rerunning safely continues cleanup.

Reports are resolved by an authorized operator, not automatically by a report
submission or the app. Record only the resolution time after reviewing/actioning:

```sql
-- Operator only, after reviewing the selected report privately.
UPDATE exp_member_community_report SET resolved_at=now()
WHERE id='REPLACE_WITH_REVIEWED_REPORT_UUID'::uuid AND resolved_at IS NULL;
```

The moderation web inbox and report alerts remain later work before public
community rollout. Review actual hosting/provider log and backup settings, state
their retention separately, and establish a private deletion-request/restore
procedure: restore into isolation, reapply deletions, validate, then reopen access.
This job does not erase a provider backup or supply a restore-erasure ledger.

## Concrete hosted handoff

1. Review these defaults and operator responsibility before authorizing live
   deletion. Keep ticket/news/community/mail/retention rollout flags off until
   their relevant gates pass. Preserve existing identity, sender and auth secret.
2. Apply **only** additive migration `migrations/009_ticket_mail_and_retention.sql`
   using the migration/operator login. Test against a restored preview copy first;
   existing accounts and threads must remain, with no backfilled jobs.
3. Create an ordinary SQL login `exp_account_jobs` using a private generated
   credential, with no admin memberships/attributes, table ownership or schema
   CREATE. Never use the preserved Neon administration roles. Apply the reviewed
   incremental app and job grants in `migrations/grants/009_account_jobs.sql`.
   The app can save preferences/queue jobs; the job role cannot grant staff,
   verify accounts, read authentication tokens or read ticket/feedback messages.
   Column-specific UPDATE on primary keys supports locking SELECT for cleanup.
4. In the **private scheduler's** secret store, set
   `EXP_ACCOUNT_JOBS_DATABASE_URL` to the account DB with this login and
   `sslmode=verify-full` (preserve Neon channel binding). No `VITE_` variables,
   credentials in cron command text, or local committed env file. Preview needs
   this DB URL only. Mail additionally needs the reviewed `ACCOUNT_PUBLIC_ORIGIN`,
   `SIGNUP_FROM_EMAIL`, `RESEND_API_KEY` and `ACCOUNT_TICKET_MAIL_ENABLED=true`.
   The website deployment separately uses that flag to start queueing new events.
   The job does not need `BETTER_AUTH_SECRET` or a Pro DB connection.
5. Run the default read-only preview and retain its private aggregate receipt:

   ```sh
   npm run jobs:accounts -- --preview
   ```

6. With approved test recipients, enable only the reviewed mail/ticket flags and
   run the member → staff reply → member read/close/delete journey. Confirm actual
   inbox/spam behavior, no body leakage, retry recovery, opt-out, grant revocation,
   cross-account isolation, logout/revocation and fresh-auth account deletion.
   A browser walkthrough and successful API acceptance do not prove delivery.
7. After approval, use the private scheduler to run the two commands separately:

   ```sh
   # Every five minutes, with the mail flag/credentials above.
   npm run jobs:accounts -- --mail
   # Daily, only with ACCOUNT_RETENTION_ENABLED=true and approved policy.
   npm run jobs:accounts -- --purge=member-retention-v1
   ```

   No scheduler or public job endpoint is installed by this source change. Use a
   scheduler that can access the private job secrets and reports failures to the
   operator. Exit 1 means configuration/storage failure or terminal mail failures
   in that batch. Output `retry` means backoff, `accepted` means provider acceptance,
   and `skipped` means no eligible recipient. Monitor failed/old pending counts in
   preview; check the actual support inbox even when no email arrives. If the daily
   purge repeatedly hits its per-table cap, review backlog before raising frequency.
8. Pause both app queueing and worker sending with the mail flag; pause deletion
   independently with the retention flag. Old app code can run against the additive
   schema. Leave the tables/indexes in place on rollback; do not drop account data.

## Verification and sources

Focused feature-gap check initially failed because the ticket email preference
was absent: `/tmp/exp-ticket-jobs-gap.log`. Fresh disposable PostgreSQL checks cover
atomic queue failure, retries, role isolation, frozen envelopes, lost provider/DB
acknowledgements, concurrent workers, pause/opt-out/revocation/deletion, expiry and
retention boundaries, batch locking/reopening, upgrade preservation and private
CLI preview/refusal/redaction. The local HTTP provider fixture verifies the actual
adapter request/header/receipt/error paths without contacting Resend.

Final `npm test` passes **144 service checks** (15 signup, 23 Pro, 92 account/job,
14 usage), plus existing native lifecycle/actual HTTP→DB checks, exit 0:
`/tmp/exp-ticket-jobs-final-all.log`. The last focused account/upgrade run also
passes 92 checks at `/tmp/exp-ticket-jobs-accounts-upgrade-final.log`.
Final browser/build matrix: `output/a11y/2026-10-18T04-31-19-895Z/report.md` —
**173 passed, zero failed/blocked, 116 incomplete contrast scans / 57 distinct
review items**. The new native checkbox is exercised using keyboard through a
held in-flight request, suppressed repeat activation, retained focus, reload and
saved choices. Actual local member → staff reply → queue processing → captured
minimal notice is checked in all four variants. Representative light/mobile and
dark/desktop ticket screenshots were inspected; horizontal containment is also
asserted in the matrix. These tests use captured mail and no external recipients.

Real hosted scheduling/deletion/provider delivery, restored-backup erasure and
human Safari/VoiceOver remain unverified. Existing incomplete contrast findings
remain review items, not passes.

Primary references checked before implementation:
[Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys),
[send-email API](https://resend.com/docs/api-reference/emails/send-email),
[PostgreSQL SELECT and locking privileges](https://www.postgresql.org/docs/current/sql-select.html).
The new choice uses a native checkbox and explicit label following
[W3C form labels](https://www.w3.org/WAI/tutorials/forms/labels/). A stricter saving
focus assertion caught Chromium dropping focus with native `disabled`; the toggle
now stays focusable with `aria-disabled`, and click/change guards suppress repeat
activation while saving. Verified before that change against
[WAI-ARIA 1.2 disabled](https://www.w3.org/TR/wai-aria-1.2/#aria-disabled),
[ARIA in HTML checkbox mapping](https://www.w3.org/TR/html-aria/#el-input-checkbox),
[APG focusable disabled controls](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/#kbd_disabled_controls)
and [WCAG 2.1 focus order](https://www.w3.org/TR/WCAG21/#focus-order).
The failed run is retained at `output/a11y/2026-10-18T04-26-52-435Z/` (two
Chromium failures, not passes). This is a bounded usability check, not a complete
WCAG 2.1 AA or assistive-technology conformance claim.
