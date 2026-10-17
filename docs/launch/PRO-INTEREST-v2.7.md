# Pro-interest confirmation — v2.7 implementation and review

October 16, 2026 · INFRA-006 · local implementation verified; public enablement pending.
Prior foundation committed as `14cb859`. No push, hosted provisioning, actual email
send or deployment occurred. Public app remains v2.6/build 17.

## Behavior to review

Open `/pro` in the local preview. It describes a **proposed** offer, preserves the
free app/download and records a preference for one-time purchase, subscription or
either depending on the benefit. This is discovery permission, not evidence of
willingness to pay: no exact paid benefit or price has been chosen.

Email permission starts unchecked. Submission creates a pending private database
record, then requests a plain-text confirmation email through the existing Resend
transport. Only an explicit confirmation button makes the record active. Visiting
an email link or making a GET request cannot confirm/cancel anything. Confirmation
links expire after 24 hours and are consumed atomically. Replaying a used link
cannot re-enroll someone after withdrawal.

A second link in that email withdraws Pro interest, also through an explicit button.
Withdrawal works even when enrollment is paused or email credentials are missing,
provided the database and public origin remain configured. It does not change the
separate release list. No general marketing permission or payment is collected.

Eight simultaneous requests produce one row and one local captured email. Eight
simultaneous confirmations produce exactly one confirmed transition. Requests
within ten minutes and already-confirmed addresses receive the same generic
response; confirmed preference/consent is not rewritten by an anonymous repeat.
After withdrawal and cooldown, rejoining requires a new confirmation email.
A mail failure invalidates only that pending token and permits a fresh retry.

## Why the database is separate

Resend remains the email delivery service. Its contact APIs do not establish the
atomic consume-once transaction needed here. A small PostgreSQL table owns the
permission record and one-time token state; the confirmed Pro cohort is **not**
automatically copied to Resend Contacts or the existing release segment.

This selects a portable storage engine, not a hosting vendor or purchased plan.
Local PostgreSQL was already installed and an isolated socket-only test cluster
was used. Hosted provider/account/region and retention remain owner review items.
No database, credentials or account from another project was reused.

Files:

- `migrations/001_pro_interest.sql`: private permission table; apply manually after review.
- `server/interest/store.js`: parameterized writes and atomic conditional confirmation.
- `server/interest/handlers.js`: validated POST contracts, origin checks, mail boundary.
- `api/pro-interest.js`, `confirm-interest.js`, `withdraw-interest.js`: Vercel entry points.
- `website/src/InterestPage.jsx`, `interest.css`: request/confirmation/withdrawal pages.
- Root `package.json`/lockfile: Node `pg` dependency; Vercel installs root and website packages.

New data: normalized email, fixed `pro_interest` purpose, preference, offer version
`pro-discovery-v1`, consent version `pro-interest-v1`, fixed `pro page` source,
request/expiry/retry/confirmation/withdrawal timestamps, and SHA-256 hashes of
random 256-bit confirmation/withdrawal tokens. No IP, document data or analytics
identifier is stored by this feature. Hashed tokens are still sensitive records.

Changing permission wording or the proposed offer requires a new consent/offer
version, not retroactively relabeling existing records.

Tokens appear in email URL fragments, not URL queries. The page immediately
removes the fragment from the visible URL and retains it in component memory only.
Reloading requires reopening the original email link. No cookies/localStorage or
analytics were added. Vercel response headers request no referrer/no caching and
exclude confirmation/withdrawal pages from search indexing; hosted header behavior
is still unverified. Resend's sent-mail storage necessarily sees the email body
including links; review its retention/access controls before enabling.

## Run and inspect locally

From the repository root, after `npm ci` and `npm --prefix website ci`:

```sh
npm test
bash scripts/preview_pro_interest.sh
```

The test runner creates a throwaway Unix-socket PostgreSQL cluster, applies the
migration and stops/removes that cluster on exit. It refuses ordinary database
URLs. It never reads hosted credentials or sends mail. The preview similarly uses
an isolated cluster and captures synthetic messages to its printed private
`/tmp/exp-interest-test.*/mailbox.json` path. Open `http://127.0.0.1:5190/pro`.
Use `@example.test` addresses and open the captured links to inspect confirmation
and withdrawal. Stop the preview with Control-C. PostgreSQL `initdb`/`pg_ctl` and
Node must be available; missing prerequisites fail explicitly.

Fresh checks: 15 existing release-signup tests plus 16 real-PostgreSQL Pro checks;
website production build; root production dependency audit reports no known
vulnerabilities. Local Chromium exercised native required consent, pending record,
visit-without-confirmation, explicit confirmation and withdrawal. Database counts
went `0 → 1 pending / 0 confirmed → 1 confirmed → 0 active`. Desktop (1280px) and
mobile (375px) screenshots were visually inspected; mobile had no horizontal
overflow. Native labels/select/checkbox and status semantics checked against W3C
sources below. Full VoiceOver/Full Keyboard Access proof remains pending.

Local receipts: `/tmp/exp-pro-interest-final-tests.log`,
`/tmp/exp-pro-interest-website-build.log`, ignored `output/playwright/pro-interest-*.png`
and `.playwright-cli/` snapshots. Captured mail and local database are disposable;
public receipts must exclude real addresses/tokens.

## Before public enablement

1. **Owner/Codex, Oct 19:** review this behavior and the new storage requirement.
   Choose the hosted PostgreSQL provider/region and private runtime role. This is
   the next setup decision; no account creation/payment is implied by this code.
2. **Codex/owner, Oct 20–21:** apply the migration to that dedicated private database
   with an owner/migration role; grant the runtime role only necessary table access.
   Do not expose this table through a public database API. Verify TLS, connection
   pooling/limits and the serverless function build/imports on an authorized preview.
3. Configure server-only `EXP_INTEREST_DATABASE_URL`, `INTEREST_PUBLIC_ORIGIN`
   (exact HTTPS site origin), existing `RESEND_API_KEY` and verified `SIGNUP_FROM_EMAIL`.
   Enrollment defaults off; set `PRO_INTEREST_ENABLED=true` only after remaining
   gates. Secrets never use `VITE_*`. Database connection failures remain errors.
4. Configure hosting/provider abuse controls before public promotion. The honeypot,
   per-address cooldown and origin checks are **not** cross-address bot protection.
   No production rate-control service is claimed implemented.
5. Test actual inbox/spam-folder delivery, fragment-link handling by real mail
   clients, expiry/retry, confirmed duplicate, withdrawal, paused enrollment and
   rejoin. Verify public-origin redirects/headers and third-party request behavior.
   Local captured mail does not establish these results.
6. **Owner/Codex, Oct 21–23:** settle seller/support/privacy contact, hosted retention,
   deletion handling and privacy copy. Choose retention for expired requests and
   withdrawn records, including mail/database backups and logs. Fresh mailbox-confirmed live-record erasure is now implemented in migration 002
   (see `ACCOUNTS-AND-PRIVACY-v2.7.md`). No automated cleanup job is included yet; launch remains gated on an
   operating deletion/retention process. Withdrawal stops eligibility; it is not
   an erasure claim. The page stays unlinked from public navigation meanwhile.
7. Before any authorized Pro email send, query the current active cohort:
   `confirmed_at IS NOT NULL AND withdrawn_at IS NULL`. Recheck permission at send
   time; never export the entire table into a mailing list. Carry a withdrawal
   route in future messages. No Pro broadcasts/export automation exists here.

The release signup still uses its existing purpose-specific Resend foundation;
this slice does **not** add mailbox confirmation to the release list. Analytics,
paid entitlements, checkout, final legal policies and release verification retain
separate gates in `RELEASE-CHECKLIST-v2.7.md`.

## Primary references checked

[PostgreSQL conditional UPDATE/RETURNING](https://www.postgresql.org/docs/current/sql-update.html),
[node-postgres parameterized queries](https://node-postgres.com/features/queries),
[Resend send email](https://resend.com/docs/api-reference/emails/send-email),
[W3C native form labels](https://www.w3.org/WAI/tutorials/forms/labels/),
[WAI-ARIA 1.2 status](https://www.w3.org/TR/wai-aria-1.2/#status),
[ARIA in HTML native checkbox](https://www.w3.org/TR/html-aria/),
[WCAG 2.1 labels/instructions](https://www.w3.org/WAI/WCAG21/Understanding/labels-or-instructions.html).

October 16 continuation: apply `002_pro_interest_erasure.sql` after 001 before
handler upgrade. The withdrawal page requests a fresh 15-minute deletion email;
`/delete-interest` requires an explicit button to delete only the live Pro-interest
row. 23 real database checks and browser flow pass. Account/member-hub target and
remaining privacy/hosting/retention work: [account foundation](ACCOUNTS-AND-PRIVACY-v2.7.md).
