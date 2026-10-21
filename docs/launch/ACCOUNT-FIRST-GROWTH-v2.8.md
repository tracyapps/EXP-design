# Account-first website and member engagement — v2.8

Owner-selected October 20, 2026. FEAT-077. Website/service work; the released
native v2.7/build 18 and open native 2.8/build 19 baseline are unchanged.

## The route through the site

The editor/download remains free and account-optional. Remove the download's
release-list form; retain the old signup endpoint/data for existing subscribers
and old clients without re-enrollment, deletion or migration. The main website
invites a free account and Pro interest, each with its own action and purpose.

A reusable paired panel appears on the homepage, download page and account
explanation page. The larger account side explains profile, preferences, news,
tickets, feedback/feature requests and member sharing. A distinct Pro side uses
the owner's `mockups/pro.svg` and links to the existing proposed-offer form.
Availability copy says tools are opening gradually. Community showcase, shared
resources/templates/components/design languages and device sync are clearly
planned, with no delivery dates or promised Pro allocation.

Checkboxes on the panels/forms request a follow-up screen only. Account signup
never creates a Pro record or mail permission. Pro interest still requires its
own explicit permission and confirmation email; its checkbox does not create an
account. The free-account form still requires its own email code and account
consent. No email, session token or capability is passed between flows in URLs.

## Sharing and signup attribution

Public copy/share tools work without an account. A member gets one random,
32-character opaque link code, generated through an authenticated account request.
Their link opens the marketing site with `?ref=CODE`; account/Pro navigation
carries that explicit context forward. No tracking cookie/localStorage, visitor
fingerprint, tracking pixel or anonymous click database is added. Hosting logs may
see the URL and remain part of the existing infrastructure data map.

Only a verified, signed-in new account can claim signup credit, and only within
24 hours of account creation. The recipient must select the separate, unchecked
`referral-credit-v1` choice. It stores recipient/referrer account UUIDs, permission
version and time. Declining makes no attribution write. Referrers see aggregate
counts, never recipients' names/emails. No self-credit, duplicate credit or later
reassignment; a recipient can withdraw from Share EXP. A withdrawn credit cannot
be re-granted. Deleting a recipient removes their credit; deleting a referrer
removes their link/events and clears that identity from others' credit records.

Share action records contain a random action UUID, actor account UUID, fixed
target and timestamp. The actor comes from the verified server session. Their
share code must match the session owner; a delayed callback after account switch
cannot record a different member's link. Target is limited to copy/system/email/
LinkedIn/Bluesky/Facebook/Mastodon. These are initiation/completion records, NOT
proof of a posted endorsement, delivery, unique readers or sales. Native share
cancellation records nothing. Clipboard failure offers an explicit manual-copy
field and records no action. Personal-link creation is not counted as a share.

There are no benefits, rewards or commissions offered or promised. Future rewards
need a separate design, terms, fraud checks, user notice/choice and any required
disclosures. Current counters must not be treated as reliable reward eligibility.

## General feedback, feature requests and testimonial permission

`/account/feedback` is independent of beta participation. Authors can save up to
50 private feedback/feature notes: type, subject (120 characters), message (1,500
UTF-16 code units), UUID and timestamps. Received means saved, not reviewed,
answered or committed to the roadmap. Support questions link to private tickets.

Testimonial permission is a separate unchecked choice on each note. It requires
a previewed first name and last initial supplied by the author, current
`testimonial-v1` wording and timestamp. No email, surname or private profile is
published, and no quote is published automatically. Consent does not enroll mail
or make a community profile public. Operators must verify CURRENT permission at
publication and preserve the meaning of the actual feedback; permission is never
inferred from a positive note, beta participation, a share or account creation.

Authors can withdraw permission or delete notes while new writes are paused or
rate-limited. Withdrawal clears the attribution label, records the withdrawal and
stops future reuse; it cannot recall already distributed materials. UI directs
people to support for an existing published quote. Deletion removes the live note
and permission; server/provider logs/backups follow their existing policy.
No public testimonial endpoint/feed or automatic publishing is included.

## Data, permissions and rollout

Additive migration: `migrations/010_member_engagement.sql`.
App-role grants: `migrations/grants/010_member_engagement.sql`.
New tables are private; PUBLIC receives no grants. All authenticated actions use
the existing origin/CSRF/abuse boundary and server-owned account identity, with
per-owner row locking, idempotency, quotas and ownership checks. No arbitrary
client actor, URL, event text or recipient field is accepted. Queries return only
owned notes/link/counters and the recipient's own credit state. Feedback caps at
50 notes and sharing at 1,000 action records; authors can clear share history.
A 60-writes/hour quota limits new writes; deletion/withdrawal bypass it.

Member records remain in the account store until author deletion/withdrawal or
account deletion; they do not inherit the opt-in usage collector's 30-day expiry.
Share codes stay until account deletion; cleared/withdrawn credit keeps only the
recipient's private, inactive permission receipt, preventing reassignment.
Existing scheduled cleanup policy `member-retention-v1` is unchanged and does
not clean these new tables. Any timed retention extension needs its own reviewed
policy/version/job grants; do not silently claim the existing job covers it.

`ACCOUNT_ENGAGEMENT_ENABLED` defaults false. Existing sign-in/profile tools work
before migration; the new section returns paused/empty data without a missing-table
failure. After migration, pausing new submissions preserves reads and author
withdrawal/deletion. Migration/flag do not enable beta, tickets, community,
telemetry, Pro mail, paid entitlements or a native account connection.

Before public enablement:

1. Review this purpose/permission/retention map and update any public privacy copy
   used for the hosted account service. Do not substitute an analytics permission.
2. Apply 010 through the existing operator process; apply the app-role grant file.
   No role creation, secrets or deployment changes are part of this local slice.
3. Deploy the reviewed source and enable `ACCOUNT_ENGAGEMENT_ENABLED=true` only
   after the schema/grants are verified. Keep other feature flags unchanged.
4. With two disposable hosted accounts, verify private feedback/withdraw/delete,
   share link, explicit optional signup credit, cross-account denial and account
   deletion. Confirm no real invite/testimonial/reward publishing was triggered.
5. Verify existing account/Pro email delivery, permissions and configured
   retention/log/backups before the marketing push. Local captured-mail tests
   prove neither hosted delivery nor operator support coverage.

Native connection/news/account display, cloud resources, showcase and sync are
roadmap candidates, not delivered native features or Pro promises in this slice.

## Sources checked

- Native form labels and explicit grouping: https://www.w3.org/WAI/tutorials/forms/labels/
  and https://www.w3.org/WAI/tutorials/forms/grouping/ .
- Web Share requires direct user activation and permits cancellation:
  https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share .
- Clipboard fallback and permission limits:
  https://developer.mozilla.org/en-US/docs/Web/API/Clipboard_API .
- Endorsement/disclosure guidance for future outreach/rewards:
  https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking .

These are implementation references, not a legal/compliance certification.

## Local verification — October 20, 2026

- `npm test`: 15 signup, 23 Pro-interest, 110 account and 14 usage-service tests
  pass, plus the native usage-consent/transport regression checks. Log:
  `/tmp/exp-growth-all-tests-final-20261020.log`.
- `npm run test:a11y -- --web-only`: 233 selected checks pass; zero failed or
  blocked; 144 automated incomplete/manual-review entries retained. Chromium
  and WebKit cover desktop dark/mobile light, keyboard account/Pro follow-ups,
  explicit recipient credit and withdrawal, copy/manual fallback without false
  share receipts, feedback/testimonial withdrawal,
  private existing account journeys and no horizontal overflow. Evidence:
  `output/a11y/2026-10-21T04-10-32-804Z/report.md`.
- New contrast failures were reproduced and corrected in the download CTA,
  account-intro light appearance and share-panel inherited text. WebKit recipient
  context now uses the same documented Option-Tab traversal as the other journeys.
- Production website build passes after final consent/deletion copy adjustments:
  `/tmp/exp-growth-build-final-20261020.log`. Backlog IDs and `git diff --check`
  pass. React review preserves hook cleanup/owner isolation and event-triggered
  writes; no extra dependencies, storage trackers or render-time writes added.
- Desktop/mobile paired panels inspected visually, including the supplied Pro SVG.
  Captures: `output/playwright/growth-panels-desktop-final.png` and
  `output/playwright/growth-panels-mobile-final.png`.

The incomplete automated findings are observations, not blanket accessibility
passes. This run uses disposable PostgreSQL and captured mail; it proves no
hosted email delivery, real social post/share delivery, VoiceOver session or
native Full Keyboard Access verification. No source commit, push, hosted
migration, deployment, email send or feature enablement was performed.

## October 20 owner-reported rollout and community follow-up (BUG-082)

Owner pushed FEAT-077 as `ed79b33`. Fresh production observations:

- Anonymous `/api/account`: HTTP 200, `engagementOpen:false`.
- Neon project EXPdesign, production branch `br-late-sunset-b5sm69kl`, database
  `exp_accounts`: zero of the five engagement tables present. Migration 010 has
  not been applied. Community table exists; zero saved drafts match owner support
  grants. Existing verified owner-grant reference matches exactly one account.
- Live community form reports a save validation error with handle `tapps`, which
  was reserved in the service. Its entered name/bio/link remain in the browser;
  the form was not navigated, cleared, submitted or published by this check.
- Vercel environment settings contain no `ACCOUNT_ENGAGEMENT_ENABLED`; the runtime
  default is false. The env-list MCP endpoint denied access; existing authenticated
  Vercel settings UI and public session metadata supplied the independent evidence.

Owner explicitly selected `tapps` for their verified owner account only. Source
fix adds migration 011 and `migrations/grants/011_owner_community_handle.sql`.
`migrations/operator/011_bind_owner_handle.sql` binds that handle to exactly the
verified account identified by the existing operator-only owner grant reference.
It refuses a missing/ambiguous owner or conflicting binding. No email or UUID is
hardcoded in source. Runtime has SELECT only on the reservation; support status,
display name or a client-supplied ID cannot acquire it. Deleting the owner clears
the binding while the name remains reserved. Other reserved names remain blocked.

Normal drafts continue working before migration 011; `tapps` fails closed with an
explicit explanation until bound. Saved drafts restore their preview on returning
to the page. Publication remains separately confirmed and respects the existing
community flag. No public publishing is authorized by the owner-handle choice.

After review and explicit authorization for hosted setup:

1. Push/deploy the follow-up source fix. Preserve the current browser draft until
   its author saves it successfully; avoid a needless reload of unsaved entries.
2. In `exp_accounts`, apply migration 010 and its matching app-role grants, then
   migration 011 and its SELECT-only app-role grant. Do not rerun already applied
   CREATE TABLE statements; confirm readiness before each application.
3. Run `migrations/operator/011_bind_owner_handle.sql` as the operator. Confirm
   exactly one `tapps` reservation, owner identity matches the verified owner grant,
   and runtime cannot INSERT/UPDATE/DELETE reservations.
4. Set only `ACCOUNT_ENGAGEMENT_ENABLED=true` in Production and redeploy so runtime
   receives it. Preserve existing flags/credentials and public-profile pause.
5. Confirm live feedback is enabled and saves/reloads privately; author can withdraw
   testimonial permission/delete. Save the owner's existing community form and
   verify preview/reload; keep public publication separate and unselected.

Verification of the follow-up: 113 account-service tests pass, including the exact
operator binding SQL (database-name guard adapted only for a disposable DB), owner
exclusivity, forged identity/staff denial, public read/report paths, deletion and
before-migration behavior. Browser rerun: 233 selected checks pass, 0 failed or
blocked, 144 retained manual-review observations. Reserved errors preserve input;
saved drafts and previews survive reload without rechecking publication consent.
Evidence: `output/a11y/2026-10-21T04-31-49-166Z/report.md` and
`/tmp/exp-owner-handle-accounts-final-20261020.log`. No hosted writes, deployment,
commit/push, email send or public profile publication performed in this follow-up.
