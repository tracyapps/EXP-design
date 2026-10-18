# EXP accounts: Neon + Vercel setup

October 17, 2026. Owner has an existing Neon account and no EXP database yet.
This began as the setup handoff. Update Oct 17: the owner connected Neon/Vercel,
corrected the auth secret/TLS URL settings and verified real email-code account
creation/sign-in. Do not recreate that working project. Project names, restricted
runtime-role grants, retention and full hosted lifecycle proof remain unverified.

**For a new isolated test environment:** create a dedicated **EXP Preview** PostgreSQL project in your
existing [Neon console](https://console.neon.tech/). Choose a US region suitable
for the site's Vercel functions; record the selected region so we can align them.
Send only the project name/region back. Keep credentials in the provider dashboard
or a password manager. No connection strings/passwords need to go into chat.

Neon is the PostgreSQL host. **Better Auth is already part of EXP's server code**;
there is no Clerk/Auth0/Supabase account to open and no Neon Auth service to enable.
Resend delivers the email codes. The website remains in the existing Vercel
`exp-design` project and account pages remain on the same origin as the website.
Manual environment-variable connection supports the existing Neon account without
installing an integration or changing the app's authentication architecture.
[Neon's manual connection guide](https://neon.com/docs/guides/vercel-manual).

## What exists and what still needs setup

| Item | Current evidence / action |
| --- | --- |
| Vercel website | Connector confirms `exp-design`, Node 24.x and `expdesign.app`. No production changes made. |
| Account pages / API | In source: `/account`, `/account/profile`, `/account/preferences`, `/account/beta`, `/account/pro`; `/api/account`. Existing SPA rewrites cover these pages; `/api/*` is excluded from SPA rewrite. No separate membership plugin required. |
| Database | Create EXP-only Neon preview project; schema and restricted runtime credentials still needed. |
| Authentication | Pinned Better Auth 1.7.10: private database sessions and single-use email codes. No separate hosted auth subscription required. |
| Sign-in mail | Verify a sender domain/address and API key in Resend. Current production mail settings are **not verified**. |
| Vercel settings | Existing connector's environment-variable listing was denied with HTTP 403; no local Vercel CLI available. Values/presence were not read or assumed missing. Use your project dashboard. |
| Public discovery | Account links are inside the account area. Main public navigation has no new account CTA. Add/review that only when the hosted flow is ready. |

## 1. Create the preview databases

Inside EXP Preview, create logical databases `exp_accounts` and `exp_interest`.
They can share the Neon project/compute while retaining separate connection strings,
roles and purposes. This is not a request for two paid accounts or auth providers.
[Neon database management](https://neon.com/docs/manage/databases).

Use the project owner/migration role only for schema work. Create ordinary login
roles `exp_account_runtime` and `exp_interest_runtime` for the website with access
only to their respective database tables; keep their passwords private. The
provider-created owner/admin role is not the runtime credential. Roles created in
Neon's console can have elevated membership; check the resulting grants rather
than assuming a new role is restricted. Operator role/password creation and grants
should be reviewed together before placing either URL into Vercel.
[Neon role behavior](https://neon.com/docs/manage/roles).

Run these existing migrations **once**, in order, using the migration role and
checking the database selected in Neon's SQL Editor:

| Database | Files, in order |
| --- | --- |
| `exp_accounts` | `migrations/003_free_accounts.sql` → `005_member_beta.sql` → `006_account_pro_link.sql` → `007_community_profiles.sql` |
| `exp_interest` | `migrations/001_pro_interest.sql` → `002_pro_interest_erasure.sql` |

Migration 004 belongs to the optional usage collector, not this account setup.
For the already working account database, apply **only unapplied migrations**;
the new community slice needs 007 and its runtime table grants. Keep its public
flag off until the moderation/retention and hosted checks in
`COMMUNITY-PROFILES-v2.7.md` are complete.
Do not rerun migrations against an existing populated schema as a reset. These
files deliberately fail on existing tables rather than overwrite stored accounts.
The code does not auto-migrate a hosted database at startup.

After migration, the operator grants schema USAGE and SELECT/INSERT/UPDATE/DELETE
on account tables to `exp_account_runtime`, and equivalent access only on
`exp_pro_interest` to `exp_interest_runtime`. No browser-facing database API or
PUBLIC table grants. Confirm account credentials cannot read the Pro database and
Pro credentials cannot read account sessions. Database owner/schema/admin access
does not belong in the deployed runtime. These grant/role checks are still pending.

From Neon's **Connect** dialog, choose each runtime role/database and its pooled
connection string for the Vercel functions. Use a direct migration connection for
schema administration. The app uses small `pg` pools and ordinary transactions;
verify them against the selected Neon pooler. Account and connected-Pro production
configuration requires `sslmode=verify-full`; Neon's copied examples may use
`require`, so update that query parameter while preserving other needed settings.
Do not disable certificate validation to make a connection work. Actual TLS,
CA/hostname verification and cold-start latency remain hosted test items.
[Neon pooling](https://neon.com/docs/connect/connection-pooling),
[node-postgres TLS](https://node-postgres.com/features/ssl).

## 2. Set private Vercel values

Use [the existing project's environment settings](https://vercel.com/tracyapps-projects/exp-design/settings/environment-variables).
The blank reference is `.env.accounts.example` in the repository root.

| Key | Value / purpose |
| --- | --- |
| `EXP_ACCOUNT_DATABASE_URL` | Pooled restricted account-role URL for `exp_accounts`, verified TLS |
| `BETTER_AUTH_SECRET` | Independent random secret, at least 32 characters; keep stable across deploys in this environment |
| `ACCOUNT_PUBLIC_ORIGIN` | Exact HTTPS origin, no path/trailing slash; preview's actual stable URL initially, `https://expdesign.app` in production later |
| `RESEND_API_KEY` | Server mail API key with permission to send from the selected sender |
| `SIGNUP_FROM_EMAIL` | Verified sender, e.g. your chosen `EXP <address@your-verified-domain>` |
| `EXP_INTEREST_DATABASE_URL` | Separate restricted role/database URL for `exp_interest`, verified TLS |
| `INTEREST_PUBLIC_ORIGIN` | Same exact site origin as `ACCOUNT_PUBLIC_ORIGIN` |
| `ACCOUNTS_ENABLED` | Initially `false`; controls registration, not existing-member privacy access |
| `ACCOUNT_BETA_ENABLED` | Initially `false`; pauses new beta choices/feedback, preserves withdrawal/deletion |
| `ACCOUNT_PRO_LINK_ENABLED` | Initially `false`; pauses new connections, preserves existing review/withdraw/disconnect |
| `ACCOUNT_COMMUNITY_ENABLED` | Initially `false`; permits private drafts/unpublish but hides public profiles and pauses publishing/reporting |
| `PRO_INTEREST_ENABLED` | Initially `false`; preserves separate Pro withdrawal/deletion when storage/origin remain configured |

Store credentials as Secret values; origins and flags can be Config values. All
keys are server-only, with **no `VITE_` prefix**. Keep Production and Preview
credentials/secrets separate. Use only synthetic/authorized test data in Preview;
do not connect arbitrary previews to production accounts. Setting generic
`DATABASE_URL` alone does not configure this app's purpose-specific URLs.
Vercel applies changed values to **new deployments**, so saving a value does not
update an already-running deployment. No deployment is authorized by this guide.
[Vercel environment behavior](https://vercel.com/docs/environment-variables).

For a new secret, this Mac command copies a generated value to the clipboard
without printing it or putting the value in shell history:

```sh
openssl rand -hex 32 | tr -d '\n' | pbcopy
```

Store it privately, then paste into Vercel. Do not generate a new auth secret on
each deploy: existing sessions and outstanding email codes depend on it.

## 3. Verify the email sender

In Resend, verify a domain you control and its required DNS records. Choose the
actual sender/support identity; don't assume the example address exists. Check
any API-key restrictions against that domain. Email codes are transactional and
do not subscribe the recipient to release, beta, Pro or general marketing.
[Resend sender-domain setup](https://resend.com/docs/dashboard/domains/introduction).

No Google/Apple OAuth app, callback registration or user password setup is needed
for this first email-code flow. The origin, mail transport and database sessions
are the relevant setup. Native Sanaa/provider sign-in is separate.

## 4. Private hosted check before opening accounts

After an explicitly authorized preview deployment, open only test registration
and the beta/Pro flags needed for that test. Check real inbox/spam receipt, wrong/
expired/replayed codes, same-origin cookie behavior, reload, sign-out everywhere,
private cross-user isolation, fresh-code deletion, feedback withdrawal/deletion and
Pro connection/withdrawal. Record exact preview origin, deployed commit and results.
Cookies must be Secure/HttpOnly/SameSite; private pages/API must remain no-store.
Confirm actual routing, IP/abuse limits and pooler connection behavior on Vercel.

Before public registration, choose and verify region, runtime role access, hosted
abuse controls, support/privacy contact and retention for accounts/feedback/auth
challenges, sent mail, hosting logs and backups—including restored-backup erasure.
The existing expiry settings and live-delete UI are not complete provider retention
policies. Core keyboard and real VoiceOver review remain separate acceptance gates.

Production should have its own isolated project/database credentials before real
members join. Do not create a populated production-data branch for general preview
testing. The optional usage collector and any payments remain separately disabled.

## Local review while setup is pending

`npm run preview:accounts` uses a disposable local PostgreSQL cluster and captures
synthetic account codes/Pro confirmation links in its private temporary mailbox.
It sends no email and does not use Neon/Vercel credentials. Visit
`http://127.0.0.1:5191/account`; `/pro` works in this same preview for the connection
journey. Stop with Control-C. `npm test` verifies the server flows locally; neither
command provisions or verifies a hosted service.
