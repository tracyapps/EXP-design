# Ticket notifications and account cleanup

October 17–18, 2026 · FEAT-069 continuation. Queue/cleanup and the protected
HTTP runner are locally verified. Additive migration 009 and incremental app-role
grants are now applied to hosted `exp_accounts`; zero queued jobs observed.
The owner selected GitHub Actions. Its environment is prepared and the approved
restricted job role was created with login disabled; the owner's LOGIN step is
now independently verified complete. Password/remaining credential entry,
live workflow execution, mail delivery and approved deletion remain pending.
Production ticket writes remain paused. Earlier no-notifier/no-job statements
in [news and private tickets](NEWS-AND-TICKETS-v2.7.md) describe their dated slices.

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

## GitHub Actions → Vercel job runner

The source workflow `.github/workflows/account-jobs.yml` runs mail approximately
every five minutes (minutes 2/7/12/…/57) and retention daily at **03:41 UTC**.
GitHub scheduling is best effort, not a five-minute delivery guarantee. Manual
choices are `preview`, `mail` and `retention`; no PR/fork trigger is present.
Pinned official checkout/setup-node actions, read-only repository permission,
no persisted Git credential, operation concurrency and a six-minute limit bound
execution. Repository/default-branch checks restrict it to `tracyapps/EXP-design`
`main`. No dependency install is needed to run the HTTP client.

GitHub receives **only** `EXP_ACCOUNT_JOB_TOKEN`, scoped to its dedicated
`exp-account-jobs` environment. It does not receive database, Resend, account-auth
or Pro credentials. The Node client POSTs only to
`https://expdesign.app/api/account-jobs`, refuses redirects and prints explicitly
projected aggregate counts only. A temporary loopback exception exists only for
non-production integration tests.

Vercel holds the matching token and `EXP_ACCOUNT_JOBS_DATABASE_URL` for the
restricted `exp_account_jobs` login. It reuses its existing sender/Resend settings.
The new endpoint authenticates the dedicated token before storage; browser cookies
or staff sessions never authorize it. It accepts only bounded JSON and the three
fixed operations. Token-unset requests fail 401. Invalid/unverified-TLS database
configuration fails closed. It has no arbitrary SQL, recipient, URL or policy input.
The Function limit is 180 seconds; the client timeout is 150 seconds. Existing mail
leases/idempotency and database cleanup locks remain the concurrency safeguards.

Mail additionally requires Vercel `ACCOUNT_TICKET_MAIL_ENABLED=true`, existing
`RESEND_API_KEY` and `SIGNUP_FROM_EMAIL`. Retention independently requires Vercel
`ACCOUNT_RETENTION_ENABLED=true` **and**
`ACCOUNT_RETENTION_POLICY=member-retention-v1`. The workflow independently requires
the matching policy variable for retention. Preview does not send or delete.

### Confirmed hosted setup — October 18

- Neon `EXPdesign` / production / `exp_accounts`: guarded additive migration 009
  committed. Both new tables and incremental existing-app-role grants verified:
  `preferences_ready=true`, `queue_ready=true`, `preference_grants=true`,
  `queue_grants=true`, `queued_jobs=0`. No backfill, live cleanup or mail send.
  Local screenshot: `output/a11y/hosted-hub-continuation-20261018/migration009.png`.
- Actual Vercel account is Hobby; its cron product supports only daily jobs.
  No paid-plan change was made. GitHub Actions was explicitly selected by owner.
- GitHub repository is public. Created dedicated `exp-account-jobs` environment
  with a **main branch-only** deployment policy. Existing Production environment
  was preserved. Repository variables `ACCOUNT_JOBS_READY`,
  `ACCOUNT_TICKET_MAIL_ENABLED` and `ACCOUNT_RETENTION_ENABLED` are all `false`.
  No environment secrets have been installed. The local workflow is not a hosted
  run. This initial preparation created no job login or Vercel job credential;
  the subsequently approved disabled role is recorded below.

### Approved role setup and credential handoff — October 18

Owner explicitly approved creating the restricted, login-disabled job role and
guided private credential setup. Created **`exp_account_jobs` with NOLOGIN** using
SQL, then applied exactly the job grants in `migrations/grants/009_account_jobs.sql`.
The guarded transaction ran in `exp_accounts` and committed. Fresh catalog results:

| Check | Observed immediately after creation |
| --- | --- |
| Login / superuser / create role / create DB / replication / bypass RLS | All false |
| Role memberships | 0 |
| Create public-schema objects | false |
| Read recipient email | true |
| Read session token / ticket message / insert support grant | All false |

No password was entered or generated for this role by the agent. Screenshot:
`output/a11y/hosted-job-setup-20261018/role-grants-verified.png`. The owner-only
handoff enables LOGIN, **initializes the password using owner-run SQL**, then
saves its `exp_accounts` pooled URL with `sslmode=verify-full` as Vercel Production
Secret `EXP_ACCOUNT_JOBS_DATABASE_URL`. Do not create a replacement role using
Neon's Add role control: the SQL-created restricted identity must be retained.
Role attributes/grants must be rechecked after the credential handoff.

Owner troubleshooting follow-up: the role appears in Neon Roles and a fresh
`SELECT rolname,rolcanlogin FROM pg_roles` confirms `exp_account_jobs` has LOGIN
enabled. Step 1 is complete. Opened only its Reset password confirmation dialog;
the original instructions asked the owner to click Reset. The owner then reports
`cannot update password for role without password`. That Reset route does not
initialize this password-less role. It is superseded by the correction below. The
agent did not submit that dialog, view a password or complete the remaining wizard.
Handoff screenshot: `output/a11y/hosted-job-setup-20261018/neon-password-reset-handoff.png`.

Corrected step 2: owner generates 32 random bytes as 64 hex characters in their
password manager or a separate Terminal (`openssl rand -hex 32`), saves the value
privately and inserts it into the prepared SQL template. The guarded DO block
refuses an unchanged placeholder or non-hex/wrong-length value, then uses quoted
`ALTER ROLE exp_account_jobs WITH LOGIN PASSWORD` on the same restricted role.
Only the owner enters/submits the password. Do not paste the resulting SQL or
history containing it into chat. The connection URL may need that saved password
inserted privately if Neon displays a placeholder; hex needs no URL escaping.

Stop the old wizard with Ctrl-C and resume the corrected one with
`bash ~/exp-account-jobs-setup-20261018.sh --from=2`. The existing running Bash
function does not automatically pick up edits. No repetition of step 1 is needed.
Local fresh PostgreSQL verifies: unchanged placeholder fails without setting
password/enabling login; valid synthetic password initializes a password-less
role and preserves restricted role attributes/column grants. Bash syntax and
unchanged-library checks pass. This does not establish hosted password completion.
SQL template: `output/a11y/hosted-job-setup-20261018/02-initialize-job-password.sql`.
Sources rechecked: [Neon role password SQL](https://neon.com/docs/manage/roles),
[PostgreSQL ALTER ROLE](https://www.postgresql.org/docs/current/sql-alterrole.html).

The owner's pushed `cb38edccddb6d2be47286caef036c73ad9996777` is production READY:
deployment `dpl_2yhxaavT7iqm65DewnwgWQH3ZVjs`, assigned to `expdesign.app`.
Fresh public `/accounts` returns 200; unauthenticated `/api/account-jobs` returns
401 with `Cache-Control: no-store`. This is deployment/access refusal proof,
not an authenticated job preview. The GitHub workflow is present/active, while
all three repository switches remain false and its dedicated environment has
no secrets at this observation.

The Vercel connector refused environment metadata access with 403; no CLI fallback
is installed. The already authenticated dashboard remains available. Its new
Production Secret form is prepared with the job-URL key and an empty value.
Browser rules require the owner to enter/confirm/submit new credentials directly;
neither a secret reveal nor a connector-authorization workaround was attempted.

A local ephemeral five-stage wizard is prepared at
`/Users/tapps/exp-account-jobs-setup-20261018.sh`:

1. Owner enables LOGIN on this existing role in the selected account database.
2. Owner initializes its first password using the corrected guarded SQL step;
   Neon's Reset control failed for the initial password-less role.
3. Owner saves the job URL only in the Vercel Production Secret form.
4. Wizard generates a random 256-bit job token in a private mode-600 file outside
   Git; owner copies it into Vercel, then the human-run wizard installs the same
   token in the explicit GitHub `exp-account-jobs` environment through stdin.
5. Return to Codex for deployment, restricted-identity verification and read-only
   hosted preview. No readiness, mail or retention flag is written by the wizard.

The local token retry file is
`~/.config/exp-design/account-job-setup/credentials.env` (or beneath the owner's
configured XDG config home). Keep it private; no DB URL/Resend/auth secret is
captured there. The wizard library was copied unchanged from the installed wizard
skill. `bash -n` passes; static tracing verifies environment scope and no rollout
flag writes. Shellcheck is unavailable. Per the skill, it was **not** run through
interactive prompts by the agent. Credential completion is not inferred from
preparing the wizard. It is intentionally local/ephemeral, not release source.

### Remaining activation sequence

1. Owner reviews/pushes this source; confirm its Vercel deployment includes the
   endpoint before configuring jobs. Keep feature flags off. Existing app/auth
   credentials remain in place; the job needs neither auth secret nor Pro DB URL.
2. The ordinary SQL role and its reviewed grants are now created and verified
   as above. Complete the owner-only LOGIN/password handoff on that existing
   identity, then recheck attributes/object privileges, including denial of auth
   tokens, message text, staff promotion and account verification. Do not recreate
   it or rerun the guarded creation transaction. Existing app grants are unchanged.
3. Add Production Vercel Secret values `EXP_ACCOUNT_JOBS_DATABASE_URL` (that login,
   `exp_accounts`, `sslmode=verify-full`, preserved Neon channel binding) and a
   random dedicated token `EXP_ACCOUNT_JOB_TOKEN` of at least 32 characters.
   Set only the matching token as an environment secret in GitHub
   `exp-account-jobs`. No `VITE_` secrets, command-line literals, committed env
   files, DB URL or Resend key in GitHub. Redeploy to apply Vercel settings.
4. Change **repository** variable `ACCOUNT_JOBS_READY=true` only after the above.
   Repository scope is necessary for the workflow's job-level condition.
   Keep the two scheduled-operation repository variables false. Manually dispatch
   `preview`; record actual run/aggregate output, confirmed restricted login and
   no changed data. An HTTP unit test or Actionlint pass is not this hosted proof.
5. With approved test recipients and operating review, separately enable reviewed
   ticket/mail flags in Vercel. Manually test member → support reply → member
   read/close/delete, actual inbox/spam delivery, independent opt-out, retries,
   grant revocation, cross-user denial and account/session deletion. API acceptance
   is not inbox delivery. Then enable repository `ACCOUNT_TICKET_MAIL_ENABLED`.
6. Keep retention off until owner approves `member-retention-v1`, provider log/
   backup periods and the restore/deletion procedure. Run a fresh preview first.
   After approval, configure policy and retention flag in Vercel, the environment
   policy variable in GitHub and repository `ACCOUNT_RETENTION_ENABLED=true`.
   Review the first actual bounded cleanup receipt before relying on the schedule.
7. Verify the owner's GitHub failure notifications/coverage. Monitor failed/old
   pending queue counts in previews and check the support inbox independently.
   Exit 1 means configuration/storage failure or terminal mail failure; `retry`
   means backoff, `accepted` means provider acceptance, `skipped` means no eligible
   recipient. If cleanup keeps hitting its per-table cap, review backlog before
   changing frequency.
8. Pause GitHub with repository `ACCOUNT_JOBS_READY=false`; independently pause
   sending/queueing and deletion with the Vercel flags. Removing/changing the job
   token revokes HTTP access after deployment. Leave additive tables in place on
   rollback; old app code remains compatible. Never reset receipt IDs/attempts to
   resend ambiguous mail.

The private direct-DB CLI remains available to an authorized operator:
`npm run jobs:accounts -- --preview`, `--mail` or
`--purge=member-retention-v1`. It uses the same restricted job login and guards.
It is a manual fallback; do not install a second scheduler for it.

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


October 18 HTTP continuation: five additional real-HTTP/PostgreSQL checks cover
missing/wrong token, methods/content/field/body bounds, paused independent gates,
read-only preview, projected CLI output, redirect/destination refusal, generic
storage errors, verified TLS configuration and actual mail/approved cleanup paths.
The HTTP provider is synthetic; no external recipient is used. Full service suite
now passes **153** cases (15 signup, 23 Pro, 101 account/job, 14 usage), plus the
existing native/wire checks: `/tmp/exp-account-avatar-final-services.log`.
Official Actionlint **1.7.12** (release checksum verified) passes the workflow.
No hosted dispatch or production deletion/send is claimed by those local checks.

Scheduling references checked against
[Vercel Hobby cron limits](https://vercel.com/docs/cron-jobs/usage-and-pricing),
[Function duration](https://vercel.com/docs/functions/configuring-functions/duration),
[GitHub scheduled events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[GitHub secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
[environments](https://docs.github.com/en/rest/deployments/environments#create-or-update-an-environment)
and [branch policies](https://docs.github.com/en/rest/deployments/branch-policies#create-a-deployment-branch-policy).
Official action release tag commits were verified before pinning.
