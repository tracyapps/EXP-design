# Optional free accounts and the privacy foundation

October 16, 2026. Owner likes accounts before Pro/subscriptions and asks about
sequencing. **Recommendation: finish the shared privacy/hosting foundation, then
add a small optional free account area before billing.** Accounts do not depend
on having a paid product. Their first useful job should determine their scope.
October 17 continuation: FEAT-069 now has a locally verified auth/private-profile/
account-display preference slice. Hosted enablement and the rest of the hub remain open.

## Owner-selected member hub

The owner selected **profile, preferences, feedback/beta participation, Pro
interest, a community profile, news/updates, opening/responding to a ticket,
an eventual Discord link, and voluntary support for the developer**. Forums are
explicitly later. This is a useful free member hub before paid subscriptions.
The earlier small-account suggestion is superseded by this target; it is delivered
in dependency-ordered slices, not represented as already implemented.

| Hub area / proposed route | First useful behavior | Permission boundary |
| --- | --- | --- |
| My profile · `/account/profile` | Display name and optional bio/links; account identity/recovery | Private by default; verified email is never public profile content |
| Preferences · `/account/preferences` | Separate release, news, Pro and beta notifications; accessibility preferences where useful | Account creation is not email permission; no auto-enrollment from legacy lists |
| Feedback + beta · `/account/beta` | Opt into beta participation; submit feedback and see its status | Private participation; no public tester directory by default |
| Pro interest · `/account/pro` | Express/review interest and payment-model preference | Link existing consent only with proof; no purchase or entitlement implied |
| Community profile · `/people/:handle` | Explicitly publish chosen display name, bio and safe links | Separate opt-in visibility, preview/unpublish/report controls; email/tickets stay private |
| News + updates · `/news` | Public release/development posts; optional notification preferences in account | Public reading stays account-free; email category permission remains separate |
| My tickets · `/account/tickets` | Open a ticket, view status and reply in the same private thread | Author + authorized support staff only; server ownership checks on every read/write |
| Community links · `/community` | Owner-configured Discord invite when ready | Plain external link first; no Discord identity linking or bot required |
| Support the developer · `/support` | Optional contribution using existing public payment profiles | Account-free, no Pro license/priority benefit; no payment data captured by EXP |
| Forums · future | Topics/discussion once the community warrants it | Later phase with moderation, reporting and retention decisions |

Profile/avatar uploads and ticket attachments need their own validation, limits
and privacy/storage proof; start with text and safe links unless those uploads
are separately admitted. Community profiles are included in the target, with
private defaults and explicit publication. Existing native feedback opens GitHub;
it does not provide the requested private ticket history yet.

Preferences across Macs and saved cloud design libraries are **additional**
native/sync features, not implied by a web account or the selected hub.

The current Pro-interest list can remain account-free. Signing up for that list
must not silently create a user account. Creating a free account must not opt
someone into release, Pro or general marketing email. Existing list contacts are
not automatically migrated into account identities.

## Dependency order and working targets

These are internal estimates, conditional on scope and hosted decisions; they are
not release commitments or estimates of owner coding time. Keep total owner work
within the existing 12–15 hours/week; budget about 2–3 of those hours for account
choices/verification in a week, leaving time for first-use and launch work.

| Target | Work | Exit evidence |
| --- | --- | --- |
| Oct 19–23 | Foundation: choose dedicated PostgreSQL host/region; verify transport, origin, inbox, deletion and retention; privacy/support contact and bot controls. Review the locally implemented account-free contribution page | Hosted receipts and operating privacy process before public enablement |
| Oct 26–30 | Auth + private profile/preferences; beta/Pro-interest linking with proof | Verified sign-in, logout/revocation, fresh auth for sensitive actions, cross-user access denied; purpose-specific permissions preserved |
| Nov 2–6 | Opt-in community profile and news/preferences; ticket schema/roles and thread design | Public/private projection tests, unpublish/report path; tickets have explicit owner/staff authorization model |
| Nov 9–13 | Private ticket creation/replies/status and owner support workflow, if foundation gates passed | Author/staff isolation tests, service notifications separated from marketing; no attachments until their separate proof |
| Nov 16–20 | Hosted hub lifecycle, deletion/recovery and keyboard/AT verification | Release only verified hub slices; core app RC/release gates remain independent |
| By Dec 1 campaign | Admit available hub benefits to public copy | No promise of unfinished tickets/community features; configure Discord only when a real owner-approved invite exists |
| Later | Forums; native preference/content sync if requested | Separate scope, moderation/sync evidence and time budget |

These are estimates for the **whole target**, not a commitment that every hub area
fits the v2.7 app release. The native app can release independently of a website
hub. If account/ticket/privacy gates miss their dates, keep those routes private
or disabled, move their rollout and describe only available benefits publicly.
Paid entitlements follow both account proof and the independent Nov 6 offer gate.

## Architecture to preserve now

- Use a stable random user ID from an established auth system. Email is verified,
  contact information, not the permanent account key. The local schema now uses
  Better Auth UUIDs. Email-change UI is deferred; no unverified email mutation is exposed.
- Keep account identity, email-purpose permission and paid entitlements separate.
  The existing `exp_pro_interest` row remains a consent record, not a login session.
  Future linking requires an authenticated subject and verified email ownership;
  matching an unverified email string never grants access or carries permissions.
- Start with a web account. Evaluate Better Auth for the current Node/React +
  PostgreSQL stack. Better Auth 1.7.10 is now pinned and locally exercised with
  database sessions, email OTP and shared PostgreSQL rate limits. The Node adapter
  is tested locally; hosted routing, transport and actual inbox proof remain gates.
- Reuse Resend as email transport where appropriate, but use the auth library's
  session, recovery, rotation and challenge handling. Existing Pro confirmation,
  withdrawal and deletion capabilities are purpose-specific; they do not sign in.
- Keep server credentials outside the browser. Server handlers enforce actual
  ownership; hiding a button or checking for a cookie in the UI is insufficient.
  Use the auth library's CSRF/session protection and a shared production abuse
  control, not a process-local counter across serverless instances.
- Native sign-in, when needed, uses the system browser authentication flow with
  authorization-code/PKCE and Keychain storage. Verify registered callbacks and
  stable app identity. No shared client secret belongs in a distributed app.
- Sanaa's connected agent/provider account remains separate; an EXP account does
  not grant AI credits or broaden document/tool permissions.
- Account creation does not enable usage analytics. Account-to-analytics linking
  would require a new explicit privacy/consent decision; current default-off
  measurement scope remains unchanged.

## FEAT-069 first account slice — locally verified October 17

Implemented routes: `/account`, `/account/profile`, `/account/preferences`, backed
by the single Node endpoint `/api/account`. Better Auth 1.7.10 owns code generation,
constant-time verification, atomic single-use consumption, signed HttpOnly cookies
and database sessions. No password, OAuth, raw auth catchall, admin, account-email
change, entitlement or native sign-in route is exposed. Same-origin JSON actions
are allowlisted; submitted user IDs, roles, public visibility and marketing flags
are rejected. The library updates only the authenticated session subject.

- Email codes expire after five minutes, with five attempts. They are stored via
  the library's custom hash option as HMAC-SHA256 using the server secret; the
  database cannot trivially brute-force six-digit codes without that secret.
- Registration requires an explicit checkbox and `free-account-v1`, recorded with
  a server timestamp. Requesting a code creates no user. Ordinary sign-in with a
  valid code cannot silently register a new account. Every profile stays private.
- The profile stores display name (80 characters), optional bio (500) and HTTPS
  website (300, no embedded credentials). Text is rendered through React escaping.
  No avatars/uploads, community publication or public directory exists yet.
- The first **working preference** is larger text in the web account area, persisted
  in PostgreSQL and applied after save/reload. It does not alter native settings.
  Release/news/beta/Pro permissions are deliberately not represented as working
  account switches yet. No list records are created, migrated or changed.
- Sign-out revokes the server session. Sign out everywhere revokes all sessions.
  Cookie caching is disabled, so replaying an old cookie cannot retain access.
  Sessions last at most seven days, with library refresh after one day.
- Live account deletion requires typing DELETE and a session created within five
  minutes by a fresh code. It removes the user/profile/preferences and cascaded
  sessions/identity rows. Separate mailing lists, design files, provider mail/logs,
  pending auth challenges, abuse records and backups have their own scope/retention.
  Inbox loss and account-email changes need a separately designed recovery process;
  passwordless access currently relies on continuing access to the verified inbox.
- Shared database IP limits: up to five code-send/verify actions per endpoint per
  minute and a general 60 requests/minute. Per-address HMAC key adds an atomic
  60-second cooldown and five sends/hour **before code rotation**, across instances.
  The Node adapter overwrites caller IP headers using Vercel's platform address or
  the direct local connection. Actual hosted proxy/bot behavior still needs proof.
- Better Auth absorbs email callback failures. Request-scoped AsyncLocalStorage
  preserves failure and prevents a false “code sent” response, including concurrent
  requests. Production transport requires a Resend message ID, with a five-second
  timeout; actual inbox receipt remains unverified.

### Setup and safe preview

`npm run preview:accounts` starts `http://127.0.0.1:5191/account` with a disposable,
socket-only PostgreSQL cluster. It prints the path to a mode-0600 temporary mailbox
file containing **synthetic test codes**. It cannot send mail. Ctrl-C stops the
server and removes that runner's database/mailbox. `npm run test:accounts` similarly
owns and removes its own test cluster. Never point these runners at a hosted DB.

Before any authorized hosted enablement:

1. Choose the dedicated product PostgreSQL host/region and least-privilege server
   role; keep account tables inaccessible to browser/public database clients.
2. Review/apply `migrations/003_free_accounts.sql` manually, before starting the auth
   service. It was generated from the pinned library, then wrapped in a transaction
   with private-profile/length constraints, PUBLIC revocation and the mail-limit
   table. No startup auto-migration or hosted migration was run. Migrations 001/002
   remain unchanged; this slice does not depend on their data.
3. Set server-only `EXP_ACCOUNT_DATABASE_URL` (production requires
   `sslmode=verify-full`), `BETTER_AUTH_SECRET` (random, at least 32 characters),
   exact HTTPS `ACCOUNT_PUBLIC_ORIGIN`, `RESEND_API_KEY` and `SIGNUP_FROM_EMAIL`.
   Never prefix secrets with `VITE_`. Test CA/hostname verification and pool limits
   on the chosen host; verified TLS is a requirement, not established by local sockets.
4. `ACCOUNTS_ENABLED=true` opens registration. With valid account configuration and
   registration paused, existing sessions/sign-in/privacy actions remain available.
   Missing email transport does not disable an existing member's logout/deletion.
   With no account configuration, the route returns 503 and the page says accounts
   are unavailable. No public account link has been added to the homepage navigation.
5. Verify actual Vercel Node handling/cookies/origin/IP limits, separate browser
   isolation, provider failures, received codes, session expiry/revocation/deletion,
   and all privacy/contact/retention choices before public registration. Do not
   rotate the signing/HMAC secret casually: sessions and pending codes depend on it.
6. Approve and operate retention/cleanup for expired challenges/sessions and abuse
   rows, sent mail and hosting/provider logs/backups, including restored-backup
   erasure. Code expiry is not a full retention/cleanup policy. Auth DB session
   tokens are library-managed credentials and must be protected as secrets.

### Acceptance evidence and next slice

`npm test`: **15 release + 23 Pro-interest + 25 account checks pass** on fresh
isolated PostgreSQL clusters. Account cases include pinned-schema matching,
creation consent, five-attempt/expiry limits, eight simultaneous code redemptions,
shared IP/address limits, delivery failure/concurrency, cross-user isolation,
unsafe fields/links, secure production cookies, logout/replay, all-session revoke,
recent-auth deletion, paused registration and real HTTP Node adaptation.
`npm --prefix website run build` and root dependency audit pass. The unavailable-service browser fixture shows a
retry/download path and no active signup form; it does not represent hosted proof.
Browser evidence uses real service/database plus captured mail for registration,
sign-in, private-profile saves, larger-text reload persistence and anonymous
isolation. A stale deletion session was refused; signing in with a fresh code
allowed explicit deletion and left the browser anonymous. Code-entry focus and
post-login heading focus were checked with keyboard Enter submission. Dark/light
mobile screenshots were inspected without horizontal overflow. This does not prove
Resend receipt, hosted configuration or formal VoiceOver/full keyboard acceptance.
Local receipts: `/tmp/exp-member-all-tests.log`, `/tmp/exp-member-build.log` and
ignored `output/playwright/exp-account-*.png`.

The beta continuation below is now locally verified. Next dependency is existing
Pro-purpose permission linking, using verified identity without copying permissions
merely because emails match. Community publication/news and private author/staff
tickets follow their own gates. Hosted setup/retention/inbox and owner AT verification
remain ahead of public enablement; native v2.7 release scope stays independent.

## FEAT-069 beta participation and feedback — local October 17 continuation

`/account/beta` uses the same private `/api/account` endpoint and library-verified
session. Participation and permission to email beta invitations/testing requests
are **separate, unchecked choices**. Participation grants no beta place, Pro access,
release/news permission or analytics enrollment. Only an explicit authenticated
choice records `beta-participation-v1` and a database timestamp. No permission is
inferred from a matching address in another system; no existing list records are
read or written. **No invitation sender or staff interface exists in this slice.**
Any future sender must check the current permission against the verified account
identity immediately before sending and prove suppression/withdrawal/delivery.

Members can submit private text feedback even without joining beta. The developer
can access these records through the private server database, but there is no
staff web route yet. Fields: subject up to 120 characters, body up to 1,500,
random UUID receipt, server creation time, verified account UUID ownership. No
files, links-as-attachments, device details or design contents are automatically
attached. React renders user text literally. “Received” means committed storage;
it makes no review/resolution claim. Replies and triage remain the ticket slice.

Storage and lifecycle contract:

- Additive `migrations/005_member_beta.sql`, after 003 in the **account** database;
  private tables with PUBLIC access revoked and account-deletion cascades. No
  dependency on or transfer from the Pro-interest ledger or usage collector.
- One current choice receipt per account (booleans, wording version, latest server
  timestamp). This is **not** a historical campaign-consent audit ledger; no sends
  or campaign evidence are claimed. Records remain until changed/account deletion.
- Up to 50 saved notes per account, with explicit per-note permanent live-store
  deletion. Participation withdrawal also switches beta invitation permission off,
  leaving feedback unchanged. Account deletion removes choices, notes and quota
  rows with the existing recent-auth confirmation. No orphan live feedback remains.
- Each submission carries one random receipt ID, retained across failed/uncertain
  retries while the draft is unchanged. Same-owner, same-content retries return
  success without new rows. Changed content or a foreign receipt conflicts with
  a generic response. Reads/deletes are scoped to the verified session subject;
  submitted user IDs, email/role/status/marketing fields and uploads are refused.
- Transactions lock the account row to serialize per-member caps and close
  account-deletion races. Thirty new notes/permission grants per member per
  one-hour window; the counter is a single private row. Read/retry/delete/withdrawal
  do not consume that quota. The library's shared IP request limit still applies;
  the quota does not waive general abuse limits. Fifty-note capacity holds under
  simultaneous writes. Storage errors roll back and never report success.
- Production enrollment/submission requires `ACCOUNT_BETA_ENABLED=true`, independent
  of account registration. The service defaults beta off; local fixture/preview
  explicitly enables it. Pausing permits existing reads/withdrawals/deletions and
  committed duplicate receipts, but refuses new enrollment/email grants or notes.
  Apply migration 005 and verify privacy/retention/transport before enabling this
  flag. Missing account configuration still returns the existing unavailable state.
- Notes have no scheduled expiry yet; the 50-note cap is not a retention policy.
  Hosted retention, operator access/audit, restored-backup deletion and provider
  logs remain owner/operator gates. Live deletion does not erase copies already in
  hosting logs/backups or sent mail. No data or email was sent to a live provider.

The screen provides native labels/checkboxes/fieldset/legend, polite status,
native delete disclosure, visible failure with preserved draft, saved history and
focus after submission/deletion. Account larger-text preference is honored. W3C
labels/grouping, ARIA in HTML checkbox/disclosure rules, WAI-ARIA 1.2 status and
WCAG 2.1 status/focus guidance were rechecked before changes; URLs in FEAT-069.

Fresh verification:

- Two initial feature checks failed because beta actions were absent:
  `/tmp/exp-beta-gap.log`. Implementation then passes 35 account service cases,
  including 10 new beta cases, against disposable real PostgreSQL. These include
  cross-user/anonymous/revoked/unverified refusal, malformed/extra fields, persisted
  choices/restart, separate invitations, withdrawal, concurrent dedup/cap, quota
  and paused operation, storage failure/retry and full deletion cascade.
- `npm test`: **87 service cases pass** (15 signup, 23 Pro, 35 account, 14 usage),
  plus existing native Swift lifecycle and actual local wire→collector→DB checks.
  `/tmp/exp-beta-all-services.log`. Website build passes:
  `/tmp/exp-beta-website-build-final.log`.
- `npm run test:a11y -- --web-only`: **93 passes, zero failures/blocked**, with
  56 incomplete scan results containing 57 distinct shared-site header/footer
  contrast review findings. None is counted as a contrast pass. Chromium and
  WebKit dark desktop/light mobile check keyboard choice/save/reload, failed POST
  with preserved draft and same-ID retry, literal text, withdrawal without losing
  feedback, explicit deletion/focus and larger account text without overflow.
  Receipts: `output/a11y/2026-10-17T21-55-59-798Z/report.md`; light mobile saved-note
  and dark large-text screenshots inspected. This does not prove actual
  Safari/VoiceOver usability, live mail, hosted configuration or complete WCAG.

Native editor and account-free workflows are unchanged. No deployment, hosted
migration, invitation delivery, staff access workflow or public-enable gate closed.

## Voluntary support page completed locally (INFRA-008)

The reference `https://plugins.tapps.design/support/` could not be opened by the
web reader, so its current local source was inspected at
`/Users/tapps/_dev/wordpress/tapps-makes-plugins-now/plugins-site/src/pages/support.astro`
and `src/data/support.ts`. It uses manual Cash App, Venmo and PayPal profile links
and visible/copyable handles. No checkout sessions or payment tracking are involved.
No files in that other project were changed.

EXP now has a static `/support.html` page and `/support` deployment rewrite, with
an unobtrusive footer link. It reuses those public profile destinations and an
adapted invitation: the shipped editor/exports remain free, voluntary support
buys neither a Pro license nor priority support. The plugins-specific “no pro
versions” promise was not copied into EXP. Links/handles work without JavaScript;
copy is an optional enhancement. Dark/light system appearance and keyboard focus
are supported. Public provider destination ownership/availability and actual
payments still require owner/live review; no payment was attempted here.

## Privacy work completed in this continuation (INFRA-007)

The withdrawal page can now request a **fresh email confirmation for deletion**.
The old withdrawal link alone cannot delete a record. A random 256-bit deletion
capability is stored as a SHA-256 hash, expires after 15 minutes and is consumed
by a conditional database DELETE. Visiting the link leaves the record intact;
the page explains scope and requires an explicit final button.

The live Pro-interest email/preference/permission row is removed. This operation
does not delete a release-list contact, any future user account, local design
files, sent email/provider logs or backups. Copy and success messages state that
scope. A missing/expired/used deletion token cannot return a false deletion success.
Enrollment may be paused while privacy operations remain available.

Apply `migrations/002_pro_interest_erasure.sql` after migration 001 and **before**
deploying code that references the new fields. Nullable additions preserve the
old handler's schema compatibility. No hosted migration was applied here.
New routes: `/api/request-interest-erasure`, `/api/delete-interest`, `/delete-interest`.
The local preview captures deletion mail alongside signup mail; it sends nothing.

Retaining sent mail/logs/backups and expiring abandoned/withdrawn records still
requires actual owner-approved periods and an operating cleanup process. This
slice implements live-record deletion, not a claim of universal erasure or a
completed legal/privacy launch gate.

## Owner review items before public policy or enablement

| Decision | Needed result |
| --- | --- |
| Member-hub rollout | Owner target recorded above; review slice order and dates against weekly verification/support capacity |
| Host/auth choice | Dedicated project, region, TLS/pooling and chosen auth schema/adapter |
| Legal seller and privacy/support contact | Actual identity and monitored contact route, not a guessed mailbox |
| Retention | Periods and cleanup owner for pending/withdrawn/active rows, mail/logs and backups; include erasure on restored backups |
| Privacy notice | Actual flows from `DATA-FLOW-AND-SIGNUP-v2.7.md`, plus confirmed hosted/account behavior; reviewed before publication |
| Account deletion/recovery | Fresh authentication, revoked sessions, purpose-specific handling and any future lawful billing retention reviewed separately |

No policies or account features were published. No hosting account, secrets,
hosted user account, production data or email was created/changed by this continuation.

## References checked before design/implementation

[OWASP authentication/session guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html),
[OWASP secure single-use/expiring challenge guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html),
[Better Auth database model](https://better-auth.com/docs/concepts/database),
[Better Auth email OTP](https://better-auth.com/docs/plugins/email-otp),
[RFC 8252 native OAuth and PKCE](https://www.rfc-editor.org/rfc/rfc8252),
[Apple ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession),
[WCAG 2.1 error prevention for deletion](https://www.w3.org/WAI/WCAG21/Understanding/error-prevention-legal-financial-data.html),
[WAI-ARIA 1.2 status](https://www.w3.org/TR/wai-aria-1.2/#status).

The OTP source describes automatic registration unless configured otherwise.
The implemented database creation hook requires explicit current account consent
and a registration intent, even after a valid code; ordinary sign-in cannot create
an account. Native OAuth remains planning research; local web-auth evidence follows.

October 17 implementation sources checked: [Better Auth installation](https://better-auth.com/docs/installation),
[email OTP](https://better-auth.com/docs/plugins/email-otp),
[session management](https://better-auth.com/docs/concepts/session-management),
[Vercel trusted request headers](https://vercel.com/docs/headers/request-headers),
[node-postgres TLS](https://node-postgres.com/features/ssl),
[W3C native form labels](https://www.w3.org/WAI/tutorials/forms/labels/).
Installed 1.7.10 source/types were also inspected for atomic verification, creation
hooks, schema generation, rate-limit persistence, recent-auth deletion and swallowed
mail failures; the executable tests establish those bounded local behaviors.
