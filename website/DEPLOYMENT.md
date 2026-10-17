# EXP [design] website deployment

The website is deployed from the same private GitHub repo as the macOS app.
Keep the Vercel project rooted at the repository root so the build can read
`docs/ROADMAP.md` and `docs/BACKLOG.md`.

## Vercel project settings

Import the existing GitHub repo and use these settings:

```text
Root Directory: ./
Framework Preset: Other
Install Command: npm ci && npm --prefix website ci
Build Command: cd website && npm run build
Output Directory: website/dist
```

The root `vercel.json` stores those same commands so Vercel should pick them up
automatically after the repo is connected.

Do not set the Vercel root directory to `website/` unless you also enable
Vercel's setting to include source files outside the root directory. The sync
script intentionally reads files from `../docs`.

## Auto-sync content

Every local or Vercel build runs:

```bash
cd website
npm run sync
```

That script reads:

```text
docs/ROADMAP.md
docs/BACKLOG.md
```

and generates:

```text
website/src/generated/siteContent.json
```

The generated JSON is ignored by Git because it includes a build timestamp and
should be recreated from the Markdown source each time.

## Daily workflow

1. Update `docs/ROADMAP.md` at the end of a work session.
2. Update `docs/BACKLOG.md` when bugs/features change.
3. Commit and push.
4. Vercel rebuilds the site from the repo root.

No manual website copy changes are needed for roadmap/backlog updates.

## Local commands

```bash
cd website
npm install
npm run dev
npm run build
```

`npm run dev` and `npm run build` both run the sync first.

## Email signup

The release signup form posts to `api/signup.js`. Signup success now requires a
saved Resend contact in the release segment/topic. Owner notification email is
optional and is sent only after persistence. Missing storage configuration returns
503; there is no notification-only success mode.

Required server-side Vercel environment variables:

```text
RESEND_API_KEY=<key with contact read/create and membership-read permissions>
SIGNUP_STORE_CONTACTS=true
RESEND_SIGNUP_SEGMENT_ID=<dedicated release segment id>
RESEND_RELEASE_TOPIC_ID=<dedicated release topic id>
```

Optional owner notification (both values required; sender domain verified):

```text
SIGNUP_TO_EMAIL=<owner notification mailbox>
SIGNUP_FROM_EMAIL=EXP [design] <hello@expdesign.app>
```

Create/verify string contact properties `source`, `signed_up_at`,
`signup_purpose`, `consent_version` before deploying. These store a request for
release updates, not verified mailbox ownership. New records opt into the release
topic only; review other topic defaults so this never grants marketing permission.
Existing contacts are not rewritten. Only verified active release topic + segment
membership yields repeat success. Opted-out/unrelated contacts require a later
mailbox confirmation/preferences flow; do not resubscribe them from the dashboard
merely to make the form succeed. Unknown membership beyond the first 100 results
fails closed. A 409 is re-read and verified, never blindly accepted.

Each provider call times out after five seconds. Rate-limit/provider failures are
reported as signup failures; owner-notification failures after persistence do not
invalidate the saved signup. Configure hosting abuse/rate controls and verify
actual provider limits before promotion. Never put credentials in `VITE_*`, source
files, browser code or command output. Do not pull/overwrite local env files just
to run the mocked tests.

Run `node --test tests/signup.test.mjs` from the repository root. Vite alone does
not serve Vercel Functions; browser verification must use a local fixture or an
authorized configured preview. Before deployment, follow the setup/migration and
hosted evidence checklist in
[`docs/launch/DATA-FLOW-AND-SIGNUP-v2.7.md`](../docs/launch/DATA-FLOW-AND-SIGNUP-v2.7.md).
In particular, concurrent provider create/upsert behavior and real unsubscribe/
confirmation/deletion are unverified. No automatic broadcasts are enabled.

## Release notifications

The simplest release-notification workflow is:

1. Publish a GitHub Release with build notes and assets.
2. Use the dedicated release segment **and** release topic, with their actual
   subscription preferences; include the provider unsubscribe/preferences link.
3. Send a Resend Broadcast manually with the release notes and direct GitHub
   release links.

A later automation can turn this into a protected Vercel Function or GitHub
Action that reads the newest GitHub Release, drafts a broadcast, and waits for a
manual send/approve step.

## Public content filtering

Website builds auto-sync progress from `docs/ROADMAP.md`; the header version
pill is read from `website/public/appcast.xml` first, with shipped roadmap
headings as a fallback for older/no-appcast states. Small website-only
maintenance entries should not clutter the public roadmap or release-notification
drafts. Add one of these markers to the progress-log title when an entry should
stay internal:

```text
[site]
[website]
[internal]
```

Example:

```text
- **2026-07-05 — Session 186 [site]:** Updated the public website...
```

## Pro-interest confirmation (local implementation; disabled by default)

The new `/pro`, `/confirm-interest` and `/withdraw-interest` pages use separate
POST endpoints and a private PostgreSQL ledger. They never add Pro requests to
the release Resend segment. Public navigation does not advertise this page yet.
Root Node dependencies are now installed as well as website dependencies.

Required server-only configuration before enablement:

```text
EXP_INTEREST_DATABASE_URL=<dedicated private PostgreSQL connection, verified TLS>
INTEREST_PUBLIC_ORIGIN=https://expdesign.app
PRO_INTEREST_ENABLED=true
RESEND_API_KEY=<existing email-transport credential>
SIGNUP_FROM_EMAIL=<verified sender>
```

Apply `migrations/001_pro_interest.sql` manually after review; no auto-migration
runs during deployment. Leave enrollment disabled until hosted delivery, abuse,
privacy/retention/deletion and accessibility gates pass. Pausing enrollment does
not disable withdrawal while its database/origin configuration remains available.
No hosted database, role or secret has been provisioned by the local work.

Full setup, data contract, local preview and verification boundaries:
[`PRO-INTEREST-v2.7.md`](../docs/launch/PRO-INTEREST-v2.7.md).

## Privacy erasure and optional support continuation

Apply `migrations/002_pro_interest_erasure.sql` after 001 **before** upgrading the
interest handlers; no hosted migration is automatic. Deletion uses a separate
fresh email link and explicit POST; privacy operations remain available while
enrollment is paused, with DB/origin configured. Erasure requests need mail
credentials; completion does not. Live-record deletion does not erase provider
mail/log/backup copies; owner-selected retention/cleanup remain required.

The static `/support.html` page works without JavaScript and opens existing public
payment profiles only on user action. `/support` rewrites there; `/support/` assets
are excluded from SPA rewriting. The footer links to the static page directly.
Copy/links do not create checkout sessions, users or paid entitlements. Review
public profile destinations and hosted routing before pushing/promotion.

Member-hub scope and phased dates: `docs/launch/ACCOUNTS-AND-PRIVACY-v2.7.md`.
No account auth, hosted database, Discord invite or ticket backend is provisioned.
