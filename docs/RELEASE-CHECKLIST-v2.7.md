# EXP design v2.7 launch readiness checklist

Opened October 16, 2026. **Only checked items have evidence; all other gates remain pending.**
Internal RC review November 16; conditional release November 20; campaign December 1.
Scope/owners/dependencies: [self-launch plan](SELF-LAUNCH-PLAN-v2.7.md).
Public v2.6/build 17 and its receipts remain immutable. Development is 2.7/18;
any release build-number change must be synchronized before packaging.

Receipts should include date, source commit, environment, command/task, result,
artifact path and owner acceptance where applicable. Private participant/contact,
payment and license records live outside the repository; use sanitized summaries.

## Distribution and ownership gate

- [x] Current unsigned Debug build and appearance regression receipts recorded.
- [ ] Full core fixture/first-use acceptance recorded.
- [x] SF Compact resource inventory covers app, helpers, design export and site assets.
- [x] Five app and 72 design-export SF binaries removed. Barlow trial resources
      and registration superseded by the owner's system-font selection.
- [x] Final standard-width system-font clean Debug build resource audit recorded;
      no OTF/TTF/WOFF/WOFF2 files present.
- [ ] Signed release app/archive contains no restricted font payload; run
      `bash scripts/verify_font_distribution.sh "APP" website/dist "design/EXP [design] Design System"`.
- [x] Owner accepts actual standard system layer titles as “clean and clear” (Oct 16).
- [ ] Full revised layer typography matrix in light/dark and Large interface type
      on both the 1x Cinema Display and a 2x display;
      standard-width system 12pt Regular/Medium selected; condensed trials superseded;
      document font records and saved files unaffected.
- [ ] Existing bundle ID/helper identities retained; no migration introduced.
- [ ] Seller identity, support contact, payment-provider eligibility and actual
      ownership documented privately by owner; entity/IP questions resolved as needed.
- [ ] Owner chooses repository license posture; third-party asset/dependency notices
      and AI-assisted provenance inventory reviewed. No automatic open-source grant.
- [ ] EULA, privacy, refund and support terms reflect actual app/site/provider behavior,
      reviewed by owner and qualified advisers where needed; published only with approval.

## Signup and privacy gate

- [x] INFRA-007 local live Pro-record deletion requires a fresh email confirmation;
      15-minute single-use token, explicit POST and seven new DB cases verified.
- [x] INFRA-008 standalone optional support page verified locally with no-JS fallback;
      no payment or hosted proof. Donation support grants no paid entitlements.
- [x] FEAT-069 free member-hub scope/permissions phased before billing in
      `launch/ACCOUNTS-AND-PRIVACY-v2.7.md`; first account slice locally verified.
      Its web rollout does not silently become a native-app launch blocker.
- [x] FEAT-069 local email-code auth/private profile/account-text preferences,
      logout/revocation and recent-auth deletion; 25 real PostgreSQL checks.
- [x] FEAT-069 local private beta/separate invitation choice, withdrawal and
      retry-safe feedback/history/deletion; 35 total account service checks.
      No invitation sender/staff workflow or hosted enablement is implied.
- [x] FEAT-069 explicit local Pro connection with dual proof, live source status,
      withdrawal and disconnect; 45 account checks across separate real databases.
- [x] Neon/Vercel setup handoff and blank environment reference prepared; existing
      project/domain metadata confirmed. Environment access denied; no settings read.
- [x] Owner verifies actual hosted email-code account creation/sign-in (Oct 17):
      “account created. looks good.” Remaining hosted lifecycle/AT checks stay open.
- [x] Local optional community draft/preview/publication/unpublish/report foundation.
      Migration 007 and moderation/retention/hosted/AT gates remain ahead of enablement;
      `ACCOUNT_COMMUNITY_ENABLED` defaults false. Contract: `launch/COMMUNITY-PROFILES-v2.7.md`.
- [ ] Hosted account lifecycle/inbox/transport/origin/bot/retention and owner AT
      proof before public enablement; remaining hub slices are separately admitted.
- [x] INFRA-006 local separate Pro request/confirm/withdraw with private PostgreSQL
      ledger; 16 real DB checks and browser flow pass. Enrollment disabled by default.
      Setup and remaining gates: `launch/PRO-INTEREST-v2.7.md`.
- [x] INFRA-005 local release-signup foundation and source data map recorded in
      `launch/DATA-FLOW-AND-SIGNUP-v2.7.md`; 15 endpoint tests + browser fixtures pass.
      This is partial evidence for the complete gates below.
- [ ] Release updates, Pro interest and optional marketing have separate purposes;
      existing release subscribers are not automatically converted to marketing.
- [ ] Durable record precedes signup success; provider/storage failure and retry
      cannot produce a false success or duplicate confirmed record.
- [ ] Real confirmation delivery, spam-folder behavior, duplicate handling,
      unsubscribe and deletion request verified with authorized test addresses.
- [ ] Proposed price/model/version and permission time stored appropriately;
      free download remains accessible without signup.
- [ ] Abuse handling, server-side secrets and log redaction checked.
- [ ] Actual data map includes website hosting/logs, Resend, Sparkle, Figma,
      Sanaa/client providers, opt-in analytics and selected payment provider.
- [x] INFRA-010 local native consent/event/collector foundation, bounded queue and
      withdrawal cancellation; private DB dedup/retention and actual local wire checks.
      Exact scope (native Save excluded) and host gates: `launch/USAGE-METRICS-v2.7.md`.
- [ ] Analytics default off; no pre-consent queue; withdrawal clears queue/identifier
      and stops transmission; deletion/retention instructions match hosted settings.
- [ ] Captured network traffic demonstrates consent-off/withdrawal behavior;
      fixed event allowlist excludes document content, paths, URLs, emails and prompts.
- [ ] Successful output events occur after successful writes only; cancel/error paths,
      retries/relaunch deduplication and offline behavior verified.
- [ ] Website clicks, app activation, marketing signups and payment records use
      distinct denominators; reports show opt-in coverage and limitations.

## Core workflow and human verification gate

- [x] INFRA-009 repeatable web/native verification harness implemented and run.
      72 web checks pass; native named-controls/Open/Escape/Cmd-S checks pass.
      Native audit findings (BUG-069) and 40 web contrast scans need review.
      AX focus passes with the exact authorized runner; new ad-hoc copies need a
      stable authorization strategy. Real reader navigation still needs verification. This does not
      close the human gates below. Run/setup: `ACCESSIBILITY-VERIFICATION.md`.

- [ ] 10–20 eligible first-use task attempts summarized; assistance explicitly recorded;
      7-day windows mature before activation rates are finalized.
- [ ] Create/import → edit → save/reopen → export/handoff completes with owned fixtures.
- [ ] VoiceOver and Full Keyboard Access pass for marketed core task, signup/consent
      and any paid surfaces; traversal/names/states/focus and failure messages recorded.
- [ ] FEAT-070 accessibility preferences accepted across supported contexts;
      default semantics available in every mode, explicit choices override Automatic,
      actual larger targets work, and persistence/live updates are verified.
- [ ] Light/dark, Large interface type, Increase Contrast, Reduce Motion and Reduce
      Transparency reviewed; blockers fixed and retested, limits stated precisely.
- [ ] Real permitted Figma file re-imported; live API/error behavior and visual results
      recorded separately from fixtures. Claims narrowed to tested coverage.
- [ ] Current SVG clips, blur export, outline/underline and BUG-055 edge cases reproduced;
      each fixed or disclosed at reliance point. Silent core data loss blocks release.
- [ ] Optional SVG clip-path slice admitted only within cap, owner-verified before
      another document mutation; unsupported constructs reported rather than guessed.
- [ ] Stale color/palette/rich-text backlog statuses reconciled from evidence;
      no invented completion claims or broad unrequested subsystem work.

## Pro offer gate — select by November 6

- [ ] Same candidate benefit shown with one-time and recurring price cards in
      balanced order; preference/fairness/usefulness and specific intent recorded.
- [ ] Owner chooses exact benefit, price/model, free boundary, refund term,
      education/hardship access, device policy and update/cancellation contract.
- [ ] Useful paid benefit specified and verified, or site explicitly remains
      Pro-interest-only. A signup is not called a purchase or presale.
- [ ] Any new paid feature fits the implementation cap and is owner-accepted;
      shipped free file access/editing/exports preserved.

Payments require all of the following; an interest-only launch does not:

- [ ] Merchant-of-record approval and actual fees/terms reviewed by owner.
- [ ] Server verifies signed webhooks; duplicate/reordered events handled idempotently;
      credentials and signing secrets absent from clients and logs.
- [ ] Sandbox purchase → receipt/key → activation → relaunch/offline → restore passes.
- [ ] Refund/revocation, expired update eligibility, subscription cancellation if used,
      second-device policy and server outage/grace behavior tested.
- [ ] Signed entitlement separates perpetual app use from update eligibility;
      eligible old-version recovery and security/free-fix policy verified.
- [ ] Authorized live purchase/refund and delivery receipt complete before paid launch.

## Freeze and release gate

Run the focused check for each changed seam. At freeze use the v2.6 regression
battery as a baseline, adding new meaningful telemetry/signup/license checks.

- [ ] `bash scripts/verify_backlog_ids.sh` and `git diff --check` pass.
- [ ] Native Debug/Release builds and `verify_appearance_style.sh` pass.
- [ ] Existing nested-component, anchored-relationship, canvas-page, XD/Figma,
      semantic HTML/package, SVG pattern/token, effect export, CodePen, rendered
      HTML/WebKit, Storybook, ruler/vector and performance checks pass with fixtures.
- [ ] Pattern-raster check runs with an explicit fixture (not the no-argument command);
      real stress-document smoke test recorded without reopening accepted old work.
- [ ] Website build and core browser/API flows pass; hosted delivery evidence separate.
- [ ] Release notes describe only verified scope and honest limits; site sync does not
      advertise the development version prematurely.
- [ ] Version/build agree across app, thumbnail and runtimes; release source frozen.
- [ ] Signed universal archive passes local release-candidate checks.
- [ ] Notarized/stapled app and clean ZIP round trip pass production checks;
      SHA-256/final byte length recorded, old artifacts unchanged.
- [ ] Owner authorizes publication; immutable download exists before feed publication.
- [ ] Appcast signature/size/build/URL verified; historical entries retained
      (`--maximum-versions 0`, `--maximum-deltas 0`).
- [ ] Public download/feed/notes/site match final artifacts after authorized deployment.
- [ ] Owner completes real v2.6→v2.7 update/install/relaunch, retaining preferences,
      recent docs, document access, file contents and free behavior.

## Campaign gate and review

- [ ] Final landscape/portrait preview approved before final render; captions and
      accessible alternatives approved; no screenshot montage called live footage.
- [ ] Marketing claims match receipts; macOS 26.2+ and Sanaa requirements visible.
- [ ] One canonical CTA selected: try EXP, Pro interest, or buy verified Pro.
- [ ] Owner authorizes actual messages/posts/placements; friend roles and support
      windows confirmed. No emails sent under preparation-only authorization.
- [ ] December 8/15 reviews report counts, correct denominators, refunds and support time.
- [ ] January 14 review chooses next scope from matured evidence.

## Session receipts

October 16: report reconciled and plan/brief written. INFRA-004 implemented;
unsigned Debug app+thumbnail+helpers build passes, identity remains 2.7/18.
Logs: `/tmp/exp-v27-launch-font-build.log`, `/tmp/exp-v27-launch-appearance.log`,
`/tmp/exp-v27-launch-website.log`, `/tmp/exp-v27-font-payloads.log`.
Distribution guard passes new app/site/design trees and rejects a known SF
filename fixture. No OTF/TTF files in new Debug app. Existing actor-isolation
warnings in untouched importer/interop code are not repaired by this slice.
Three-page collaborator DOCX rendered and visually reviewed. No owner typography,
AT, hosted delivery, checkout, signed-release or upgrade proof is inferred.
No release, commit or public campaign occurred.

Barlow trial follow-up, October 16: `/tmp/exp-v27-barlow-build.log` succeeds;
`/tmp/exp-barlow-registration.log` confirms actual bundled Light/Medium faces
and process-scoped repeat registration. Apple font distribution guard passes.
The earlier no-TTF Debug receipt describes the superseded system-font build;
that superseded candidate intentionally included licensed Barlow TTFs and OFL.txt.
Owner visual acceptance remains open.

Standard-system-font follow-up, October 16: clean Debug app+extension/helpers build
succeeds (`/tmp/exp-v27-standard-font-build.log`). No embedded font binaries in
new app; `verify_font_distribution.sh` passes. Actual shared SwiftUI layer-label
seam matches 12pt system Regular/Medium reference pixels at both 1x and 2x
(`/tmp/exp-standard-layer-font-probe.log`). This is rendered-seam/source evidence;
owner real-window/display acceptance and signed release audit remain pending.

October 16 owner acceptance and signup follow-up: owner accepts standard system
layer titles as “clean and clear”; complete matrix/AT/signed archive still pending.
`node --test tests/signup.test.mjs`: 15/15, exit 0 (`/tmp/exp-signup-tests.log`);
website build exit 0 (`/tmp/exp-signup-website-build.log`). Local Chromium CLI
fixtures prove 503 stays failed with download link available, empty JSON HTTP 200
is rejected, and `ok:true` redirects to intercepted release fixture. Snapshots:
`.playwright-cli/page-2026-10-17T02-02-00-124Z.yml`,
`.playwright-cli/page-2026-10-17T02-02-08-626Z.yml`,
`.playwright-cli/page-2026-10-17T02-02-27-590Z.yml`. Times are UTC; owner date Oct 16.
Expected browser resource error was the injected 503. The CLI default Chrome path
was unavailable; existing cached Chromium was selected explicitly. No live Resend
requests/sends, configuration changes or deployment. Concurrent provider creation,
actual limits/delivery/unsubscribe/deletion and Pro confirmation remain unverified.

INFRA-006 follow-up October 16: `npm test` executes 15 release checks + 16 Pro
PostgreSQL checks, all pass. Pro tests include eight concurrent requests and
confirmations, expiry, withdrawal, replay, mail failure/retry and paused enrollment.
Local browser uses real handlers/DB and captured test mail; unchecked consent blocks
submission; record counts move 0 → 1 pending → 1 confirmed → 0 active. Desktop/mobile
screenshots inspected; full AT pending. Website production build and root production
dependency audit pass. No hosted function/DB/mail proof or privacy/abuse closure.

October 16 continuation: 15 release-signup + 23 real PostgreSQL checks pass;
seven added erasure tests cover fresh mailbox capability, atomic concurrent DELETE,
expiry, request dedup, mail failure/retry, paused enrollment and stale-cycle tokens.
Browser captured-mail/real-DB deletion is verified; generic POST response is not
called universal erasure. Support page checked with isolated clipboard boundary,
JavaScript disabled, mobile width and light/dark screenshots; live providers and
payments unverified. Auth/accounts/ticket/community implementation remains planned.


October 17 FEAT-069 first account slice: `npm test` passes **63 total** (15 release,
23 Pro-interest, 25 account on real isolated PostgreSQL); current website build
passes and root production audit reports zero known vulnerabilities. Browser uses
actual auth handlers/DB and captured synthetic mail for registration/sign-in,
private profile and larger-text persistence; dark/desktop and light/mobile images
inspected, no horizontal overflow; fresh browser is anonymous. Recent-auth deletion
rejection is surfaced with a reauthentication instruction; fresh code sign-in then
explicit deletion succeeds and leaves the browser anonymous. Code-entry/post-login
focus and Enter submission checked. No hosted mail/routing/
TLS/provider/retention or formal VoiceOver/FKA proof. Handoff:
`launch/ACCOUNTS-AND-PRIVACY-v2.7.md`; migration 003 awaits authorized hosted apply.
Receipts: `/tmp/exp-member-all-tests.log`, `/tmp/exp-member-build.log`, ignored
`output/playwright/exp-account-*.png`. Native app remains unchanged; no push/deploy.


October 17 INFRA-009 accessibility harness: final integrated run
`npm run test:a11y -- --interactive` records **72 passing web checks** across
Chromium/WebKit and two appearance/viewport variants each. Forty incomplete
contrast scan entries contain 57 distinct rule/selector findings for human review.
Native XCTest records **two passed, one failed audit test (27 findings), one skipped
focus test**; real VoiceOver is separately blocked by its scripting setting.
The command exits 1 because the audit findings remain failures. This does not
close the human accessibility gates. Evidence:
`output/a11y/2026-10-17T05-59-43-060Z/report.md`, `review.json`,
`native/findings.md`, `native/summary.json` and `native/results.xcresult`.
The native screenshots inspected are cropped to the disposable editor window.
Fresh website build, 63 existing service tests, project plist validation, script
syntax and backlog-ID guard pass; website dependency audit reports zero known
vulnerabilities. Logs: `/tmp/exp-a11y-final.log`,
`/tmp/exp-a11y-services-final.log`, `/tmp/exp-a11y-build-final.log`.
Setup and repeat instructions: `ACCESSIBILITY-VERIFICATION.md`. Live VoiceOver
traversal/cleanup awaits the OS permission gate; no push, deploy or provider sends.


October 17 FEAT-070: Settings → Accessibility provides independent interface text,
larger shared targets and visible guidance. Public VoiceOver status controls only
Automatic guidance; explicit choices remain authoritative. Shared text actually
scales, control padding accepts clicks, and live Settings changes are verified.
Policy/persistence checks and two VoiceOver matcher regressions pass; the final
three-case focused UI run passes in `output/a11y/interface-final-20261017/`.
Combined native run `output/a11y/2026-10-17T14-25-39-868Z/` has five workflow passes,
one skipped focus test for the fresh runner and 23 retained audit observations.
Strict real-reader traversal still fails despite captured speech. Dark snapshots
inspected; full display/appearance/settings and selected-object/AT gates stay open.
Build: `/tmp/exp-interface-hints-build.log`; scope: `ACCESSIBILITY-VERIFICATION.md`.


October 17 owner refinement (BUG-070): duplicate type size removed from General;
General now contains explicit Drawing toolbar labels, and Accessibility owns text,
targets and Panel help text. Legacy presentation choices migrate without reset.
Properties uses bounded, reflowing inset/layout controls and compact native
Pathfinder icons. Focused receipts/scope: `ACCESSIBILITY-VERIFICATION.md` and
`output/a11y/panel-fit-confirmed-20261017/native/results.xcresult`.
These source/runtime refinements do not mark the full visual/AT release gates done.


October 17 FEAT-071 / BUG-071 / BUG-072: first-pattern authoring, direct fill
editor opening, editable pattern/component dimensions and artwork fit; ordinary
peer ordering for detached trays, reveal commands and canvas-display Settings.
Four focused native UI tests pass, zero failures/skips; model/raster/save/legacy,
86 SVG pattern checks and nested component checks pass. Build includes thumbnail.
Evidence, precise geometry-fit definition and pending owner checks:
`SOURCE-BOUNDS-VERIFICATION.md`. These focused results do not close physical
multi-monitor, full 1x/2x/appearance/VoiceOver or signed-release gates.


October 17 owner acceptance: "all of those passed. works well." closes the
FEAT-071/BUG-071/BUG-072 pattern/component authoring and window-ordering review.
The broader accessibility, hosted lifecycle and signed-release gates remain open.


October 17 INFRA-010: local native consent/relaunch/revocation, actual edit and
cancelled/completed handoff, and ordinary-build unavailable state pass three native
UI cases without skips/failures. Fourteen private PostgreSQL/collector cases and
Swift lifecycle/retry/race checks pass, with actual local URLSession→HTTP→DB proof.
Website build, 15 release-signup, interface policy and source-bounds/raster checks
pass. Exact receipts/limits: `launch/USAGE-METRICS-v2.7.md`. Production has no app
endpoint or enabled collector; hosted logs/backup/edge/daily retention, packaged
traffic and full owner/AT gates stay open. Native Save/Auto Save is uninstrumented.

Combined launch-service regression after INFRA-010: `npm test` passes all 77
signup/interest/account/usage cases plus the Swift lifecycle/race and actual native
wire→collector→DB checks. Log: `/tmp/exp-usage-services-regression.log`.

October 17 FEAT-069 beta continuation: `npm test` passes **87 service cases**
(15 release, 23 Pro-interest, 35 accounts, 14 usage) plus the existing Swift
lifecycle and actual wire→DB checks. Website build passes. Web suite passes
**93 checks, zero failures/blocked**, with **56 incomplete scans / 57 distinct
shared header/footer contrast review findings** left open. Four Chromium/WebKit
dark-desktop/light-mobile journeys include beta choice persistence, failed-post
draft retention and same-id retry, escaped feedback text, withdrawal, explicit
deletion/focus and larger account text. Screenshots inspected without overflow.
Receipts: `/tmp/exp-beta-all-services.log`, `/tmp/exp-beta-website-build-final.log`,
`output/a11y/2026-10-17T21-55-59-798Z/report.md`. Native app unchanged. Migration
005 remains local only; beta new-write flag defaults off. Hosted lifecycle,
mailbox/provider, logs/backups/retention, staff workflow and real VoiceOver remain
open; these results do not close public-enable or full AT gates.

October 17 FEAT-069 Pro connection/setup continuation: `npm test` passes **97 service
cases** (15 signup, 23 Pro, 45 account, 14 usage), plus existing Swift/native-wire
checks. Website build/browser matrix passes **109 checks**, zero failures/blocked,
with **68 incomplete contrast scans** still needing shared-site review. Actual
preview HTTP smoke passes registration, captured Pro mail, confirmation, explicit
connection, withdrawal and account deletion. Receipts:
`/tmp/exp-account-pro-all-tests-final.log`, `/tmp/exp-account-pro-preview-smoke.log`,
`output/a11y/2026-10-17T22-15-22-098Z/report.md`. Initial web run retained at
`output/a11y/2026-10-17T22-13-36-592Z/`: one bounded keyboard helper omitted its
post-final-Tab focus check; target was focused in the failure screenshot. Helper
fixed and full suite rerun. No hosted enablement, provider email or actual
Safari/VoiceOver proof. Neon setup guide records remaining owner/operator steps.

October 17 FEAT-069 community continuation: owner confirms hosted account creation
and the resulting signed-in experience. The optional community foundation passes
**107 service cases** (15 signup, 23 Pro, 55 account, 14 usage), plus existing native
lifecycle/wire checks; final browser matrix passes **133 checks**, zero failures
or blocked, with **88 incomplete contrast scans** left open. Mobile editor/public
profile and dark desktop editor screenshots inspected without clipping. Journeys
cover explicit preview/consent/publication, result focus, public field isolation,
literal rendering, verified private reporting and unpublish→not-found. Initial
failures and fixes are preserved in `launch/COMMUNITY-PROFILES-v2.7.md`.
Receipts: `/tmp/exp-community-all-tests-confirmed.log`,
`output/a11y/2026-10-18T00-23-50-317Z/report.md`. Migration 007 remains unapplied
to hosted storage; public community flag defaults off. Hosted operator moderation,
retention/logs/backups, abuse controls and human Safari/VoiceOver remain open.
No agent deployment, provider email or public profile was created.
