# Optional free accounts and the privacy foundation

October 16, 2026. Owner likes accounts before Pro/subscriptions and asks about
sequencing. **Recommendation: finish the shared privacy/hosting foundation, then
add a small optional free account area before billing.** Accounts do not depend
on having a paid product. Their first useful job should determine their scope.
No EXP account authentication/session system is implemented by this document.

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
  changeable contact information, not the permanent account key. No user/profile
  table is added until the auth schema/provider is chosen.
- Keep account identity, email-purpose permission and paid entitlements separate.
  The existing `exp_pro_interest` row remains a consent record, not a login session.
  Future linking requires an authenticated subject and verified email ownership;
  matching an unverified email string never grants access or carries permissions.
- Start with a web account. Evaluate Better Auth for the current Node/React +
  PostgreSQL stack; it supports database-backed identities/sessions and email OTP.
  This is a candidate, not an installed provider or a hosted-account decision.
  Verify its serverless adapter/schema/rate-limit configuration before implementation.
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
user account, production data or email was created/changed by this continuation.

## References checked before design/implementation

[OWASP authentication/session guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html),
[OWASP secure single-use/expiring challenge guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html),
[Better Auth database model](https://better-auth.com/docs/concepts/database),
[Better Auth email OTP](https://better-auth.com/docs/plugins/email-otp),
[RFC 8252 native OAuth and PKCE](https://www.rfc-editor.org/rfc/rfc8252),
[Apple ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession),
[WCAG 2.1 error prevention for deletion](https://www.w3.org/WAI/WCAG21/Understanding/error-prevention-legal-financial-data.html),
[WAI-ARIA 1.2 status](https://www.w3.org/TR/wai-aria-1.2/#status).

The OTP source describes automatic registration unless configured otherwise;
future implementation must deliberately separate account creation/consent from
sign-in rather than inherit that default accidentally. Native OAuth/auth-library
behavior is planning research here, not freshly executed proof.
