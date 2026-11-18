# Team research and social previews — November 17, 2026

Owner requested codebase work: check social thumbnails; implement the small
team-interest survey; make survey/message-library copy sound more like their
published case studies. Implemented locally. No commit, push, deployment, hosted
migration, email send, or actual research collection performed.

## Account inbox and activation (November 17 continuation)

The owner approved the team page and tone. Added a private **team research**
section at `/account/team-research`, linked from the account menu. Server-side
Better Auth session checks restrict reads to the verified `tracyapps@gmail.com`
account. No admin email env var is needed. Other members cannot read responses.
The inbox shows 25 responses at a time, newest first, with refresh and older-page
controls. Only confirmed follow-up addresses are returned. No management tokens,
unconfirmed email addresses or confirmation tokens are exposed in this API.
Refresh before contacting someone to check their current permission.

### Setup before opening the form

1. In the **interest database**, apply `migrations/013_team_research.sql` if not
   already applied, then `migrations/014_team_research_inbox.sql`. Apply their
   matching files in `migrations/grants/` for the existing `exp_interest_app` role.
   Do not rerun already-applied migrations. No account-database migration is needed.
2. Keep the existing server-side `EXP_INTEREST_DATABASE_URL`,
   `INTEREST_PUBLIC_ORIGIN=https://expdesign.app`, `RESEND_API_KEY`, and
   `SIGNUP_FROM_EMAIL`. The account service must already be configured, and
   `ACCOUNT_PUBLIC_ORIGIN` must match the interest origin.
3. Set these **server-side production** variables (never prefix them with `VITE_`):

   ```dotenv
   TEAM_RESEARCH_ENABLED=true
   TEAM_RESEARCH_POLICY=team-research-90d-v1
   TEAM_RESEARCH_NOTIFY_OWNER=true
   CRON_SECRET=<random secret of at least 32 characters>
   ```

   Keep an existing suitable `CRON_SECRET`; do not rotate a shared secret just
   for this feature. Policy acknowledgement means accepting the 90-day response
   retention and daily cleanup described below.
4. Deploy the website/API changes and verify the protected daily cron is active.
   `vercel.json` schedules `/api/team-research-jobs` at 12:00 UTC daily. The job
   clears expired records and pending contact details, and retries up to five
   queued notification emails per run. It remains active with collection paused;
   keep the policy, DB/origin and cron secret configured when pausing collection.
5. Sign in as the verified owner and open **team research**. Verify a synthetic
   submission, email notification, confirmed contact, withdrawal and deletion
   before sharing the form publicly. Check the cron execution logs too.

Each saved response attempts an owner notification when enabled. The email goes
only to `tracyapps@gmail.com` and contains a sign-in link and response reference;
answers/contact details remain in the private inbox. Delivery failure does not
lose the saved response. Leases and provider idempotency reduce duplicate sends;
this is not an exactly-once delivery guarantee. Five unsuccessful attempts stop
retries and show a warning in the inbox. Existing unexpired responses are also
eligible for a notification when enabled. Daily retries are deliberately bounded,
so a backlog may take multiple runs. No automatic sales follow-up is sent.

Implementation and settings instructions are local only: no production variables,
hosted migrations, deployment, scheduled execution or real emails changed here.

## What changed

- `/teams`: account-free survey with skippable role, size, pain, computers,
  essential-tool categories and adoption barrier. Optional technical/approval
  details use native disclosure. One nonempty answer is enough to submit.
- Confirmation of a saved response precedes an optional email/permission form.
  Survey answers are not contingent on email delivery or email confirmation.
- Separate `team-research-contact-v1` permission, separate table. No changes to
  existing Pro/account/news permissions. No automatic marketing enrollment.
- Follow-up needs an explicit email confirmation within 24 hours. GET changes
  nothing. `/teams/confirm` and `/teams/manage` consume fragment capabilities in
  component memory and remove them from the address bar. Reload requires the
  original private link; these pages do not put capabilities in browser storage.
- Respondents receive a private management link immediately after saving, even
  without email. Anyone holding it can stop follow-up or delete that response.
  Stop-follow-up clears the email/consent/confirmation but retains survey answers.
  Delete removes the whole live record. Both work with enrollment/mail paused.
- Client-generated 256-bit capability also makes a retry idempotent. A repeated
  submission with different answers explicitly reports that the earlier answer
  was already saved, rather than falsely claiming the edit was saved.
- Read-only operator SQL provides current answers and ONLY confirmed, unexpired
  follow-up addresses. Recheck live permission before any contact.
- Linked from the shared learn navigation/footer and the Pro page. Collection
  remains unavailable until server-side enablement and policy acknowledgement.
- Survey, Pro intro and message library use lowercase, concrete language and dry
  asides. The library now leads with a returning-product update, not a first launch.
  Voice based on the available `add-case-study` skill and published examples;
  no global skill was created or modified.

## Social preview findings

Existing source already had Open Graph/Twitter metadata and a real 1200×630 PNG
at `/assets/share/exp-social.png`. The image was visually inspected and retained.
Added explicit homepage canonical/secure image metadata and build-time checks
that verify the generated HTML, unique tags, dimensions, PNG bytes and file size.
`/teams` gets its own static HTML metadata and canonical via a postbuild step and
Vercel rewrites, so crawlers don't need to execute React. `/share` is also checked.

Live verification was unavailable: shell DNS lookup failed, web retrieval could
not fetch the PNG, and the browser-control runtime failed. This does NOT establish
a live missing-image defect. No claim that LinkedIn or any social network has
refreshed a cached preview. After deploy, inspect raw HTML and image HTTP status /
content type from the public domain, then use the relevant network's preview
inspection tool if the old thumbnail persists. No new artwork was needed.

## Storage and operations

Migration: `migrations/013_team_research.sql`, applied to the existing private
interest database, not the account database. Grants:
`migrations/grants/013_team_research.sql` for existing `exp_interest_app`.
No broad public grants, accounts, credentials or vendor services created.

Data: bounded answers JSON, survey version, creation/expiry, optional email,
versioned contact permission, request/confirmation timestamps, retry time and
hashed confirmation/management capabilities. No survey-level IP, fingerprint,
account identifier, browser storage or tracking pixel. Infrastructure logs and
mail delivery have their own data handling. Do not label this anonymous.

Backend: `POST /api/team-research`, allowlisted operations and field names, exact
origin, JSON only, 12 KB request limit, length/enum validation, generic errors and
logs. Global SQL-backed budget: 60 saves/minute, 30 contact attempts/minute;
per-address hashed budget: 3/hour; each response has a 10-minute mail cooldown.
Global budgets can be exhausted by an attacker, so hosting abuse controls still
matter. The public form has a honeypot; it is not a substitute for those controls.

Retention policy identifier: `team-research-90d-v1`. Proposed implementation:
responses expire after 90 days; unconfirmed addresses cleared after 24-hour link
expiry; budget rows removed after a day. A daily operator job performs physical
cleanup. Until that job and the policy are operationally accepted, leave collection
off. Confirmed contact eligibility always excludes expired records even if cleanup
is delayed. Deletion cannot promise removal of already-sent mail, host logs or
provider backups; page copy distinguishes those copies.

`node scripts/team_research_retention.mjs` previews counts only.
`node scripts/team_research_retention.mjs --apply` performs cleanup using
`EXP_INTEREST_DATABASE_URL`. The protected daily scheduler is now defined in `vercel.json`; it is not deployed
or enabled in production in this session.

`migrations/operator/team_research_review.sql` reads responses for the owner.
Its output is private; do not publish or put it in source control. No public
response-list API, contact broadcast or automatic sales follow-up exists.

## Verification receipts

Passed locally:

- `npm run test:teams:contracts`: 25 checks, covering validation, consent and HTTP
  boundaries, failed persistence/mail, status results, paused deletion, and
  server-rendered native labels/grouping/disclosures. Storage is injected in these
  contract tests; they do not prove PostgreSQL queries or browser interaction.
- `npm --prefix website run build`: Vite production build plus static `/teams`
  generation and metadata/image checks for homepage, teams and sharing pages.
- `node --test tests/signup.test.mjs`: all 15 existing release-signup tests pass.

Blocked / not established:

- `npm run test:teams`: isolated PostgreSQL initialization fails at `shmget`
  with “Operation not permitted” in this sandbox. The 19 integration scenarios
  are written in `tests/teams.test.mjs` but did not run. The added real-session
  account authorization integration test is likewise unverified. They cover persistence,
  concurrent retries/confirmation, permission, erasure, expiry and mail failure.
- Chromium launch fails at macOS MachPortRendezvous bootstrap with “Permission
  denied.” No actual desktop/mobile screenshots, browser interaction, axe pass,
  VoiceOver or keyboard completion is claimed.
- Hosted DB migration/grants, public routing/headers, actual inbox delivery,
  cleanup scheduling and live social preview remain unverified.

## Next verification / rollout

1. In a terminal that permits local PostgreSQL, run `npm run test:teams`.
2. Run `npm run preview:teams`. It starts an isolated socket-only database and
   the real website/API at `http://127.0.0.1:5191/teams`. It captures email to a
   private `/tmp/exp-team-test.*/mailbox.json`; it cannot send real mail.
3. Try a one-answer response, a more detailed one, confirmation, withdrawal,
   deletion, and a repeated request. Use synthetic `@example.test` addresses.
   Check narrow/mobile layout, keyboard/focus, status announcements, light/dark
   behavior inherited from the site, and VoiceOver. Original email links must be
   reopened after a management-page refresh.
4. After local proof and approved hosted rollout: apply migration/grants with
   the operator role, including migration 014 and its sequence grant. Verify the restricted runtime role can use only its tables.
5. Retain existing server-only `EXP_INTEREST_DATABASE_URL`,
   `INTEREST_PUBLIC_ORIGIN`, `RESEND_API_KEY`, and `SIGNUP_FROM_EMAIL`. Set
   `TEAM_RESEARCH_POLICY=team-research-90d-v1` only with the stated retention,
   access, provider-copy handling and daily job accepted/operational. Set
   `TEAM_RESEARCH_ENABLED=true` when the flow is ready. Neither belongs in VITE env.
   Missing flag or policy keeps collection/confirmation off. Withdrawal/deletion
   remain available with DB/origin alone.
6. Verify real inbox/spam delivery, expiry, stop/delete, no permission changes to
   other lists, deployment routing/headers and provider abuse protection. Inspect
   the actual social card on the public domain. Then share `/teams` publicly.

## Accessibility references checked before implementation

- https://www.w3.org/WAI/tutorials/forms/labels/ — visible native labels.
- https://www.w3.org/WAI/tutorials/forms/grouping/ — fieldset/legend grouping.
- https://www.w3.org/WAI/WCAG21/Understanding/status-messages.html — status feedback.
- https://www.w3.org/WAI/ARIA/apg/practices/read-me-first/ — native semantics first.
- https://ogp.me/ — image properties and canonical object URL.

No new custom widget role is introduced; optional details use native disclosure.
Existing navigation/appearance implementation was not redesigned in this slice.
