# EXP design v2.7 self launch plan

Owner direction recorded October 16, 2026: self-launch, Pro signup, analytics,
verification and licensing; reconcile the sellability report with the existing
product. Capacity: **12–15 owner hours/week**. Test **one-time purchase and
subscription** with prospective users before selecting either. Dates below are
internal targets in America/Chicago, conditional on evidence, not public promises.

**Outcome:** make EXP safe to distribute, easy to try, measurable by consent and
ready for an honest paid offer. Keep its native canvas, useful free access,
semantic handoff and consented agent workflow at the center. The report supports
this experiment; it does not prove product-market fit or a valuation.

Status October 16: plan and collaborator brief complete; INFRA-004 font remediation
implemented; owner selected standard-width system 12pt Regular/Medium after
condensed-font comparisons. Final build/display acceptance remains tracked in
the release checklist. All other
implementation/hosted/checkout gates remain pending.

Start here for execution. [Release gates](RELEASE-CHECKLIST-v2.7.md) hold receipts;
[marketing brief](MARKETING-BRIEF-v2.7.md) is for collaborators;
[source checks](SELF-LAUNCH-SOURCES-2026-10-16.md) support commercial decisions.
ROADMAP remains the authority for scope and session continuity.

## Decisions and boundaries

- v2.7 is the **commercial-readiness cycle**. The scoping gate is satisfied for
  the bounded work below. No claim that any of it is already implemented.
- Existing shipped editing, file access and exports remain available. No file
  hostage behavior, export watermarks, document quotas or compulsory account.
- Pro interest is an explicit **proposed offer**, not a pretend checkout. Payments
  wait for a defined deliverable, working fulfillment and reviewed terms.
- A useful permanent free tier, education and hardship access are design
  constraints. Exact eligibility/issuance terms are still to be decided.
- Retain `tapps.EXP--design-` and existing helper/thumbnail identities. Renaming
  is unnecessary for selling and risks settings, sandbox and updater continuity.
- New document-mutating work remains sequential: build one slice, get owner
  acceptance, then start the next. Non-mutating docs/site work can proceed.
- No Windows port, collaboration platform, investor process, sale process or
  broad typography/color overhaul in this cycle. Collect platform requests in
  interviews; do not start another public waitlist competing with the Mac CTA.
- Public posting, email sends, paid placements, account agreements, final video
  rendering and deployment require their own owner authorization. This plan
  authorizes preparation and bounded implementation, not those external acts.

## What survives from the report and what changes

| Report recommendation | Current evidence and reconciliation | v2.7 treatment |
|---|---|---|
| Self-launch before investors or sale | Product/release evidence exists; demand evidence has not been established | Adopt Route A; interviews, activation, priced interest, then purchase evidence |
| Five bundled SF Compact fonts | Files, registration call and warning exist in source; Apple license restricts embedding | First implementation slice; remove restricted resources, preserve readable chrome |
| Rename generated bundle ID | Already shipped with this identity; Sparkle assumes stable identity | Reject routine rename; verify upgrade/data continuity instead |
| EULA/privacy/refunds and ownership | No root LICENSE; report's entity and assignment advice is conditional | Draft actual data map, notices and terms; owner selects seller and reviews legal/tax questions |
| Analytics and activation | No product funnel implementation found; existing diagnostics are local and user-driven | Minimal opt-in website/app events; separate transactional records and marketing permission |
| Pro/signup machinery | Existing `/api/signup` sends notification; optional contact storage can fail without failing success | Durable separate Pro-interest record; explicit success, confirmation and unsubscribe; test delivery |
| Help/video publishing | `/learn` already has deployed clips; promo compositions await final approval/render | Reuse existing content; package three stories, approve/render once; no duplicate production spree |
| VoiceOver/FKA verification | Control audit has live gaps; v2.6 release explicitly does not claim formal AT coverage | Core-task audit is a release gate; source labels and green builds are insufficient |
| Figma fidelity closure | Interop plan still records live acceptance and edge cases open | Re-import a real permitted file; report exact limits; close launch-demo blockers only |
| SVG clip-path/CSS masks | SVG exporter and native masks exist; inventory covers a much larger future capability set | One bounded SVG clip-path candidate after core gates; no promise of full CSS mask support |
| Background blur and inner shadow | Export parity gaps/BUG-055 remain; BUG-034 Stage 2 intentionally parked | Test marketed demo; truthful warnings or bounded fixes, no silent loss; do not reopen parked work |
| Color/palette/token completeness | ROADMAP Phase 18 closed; older backlog statuses lag shipped controls/import/export | Reconcile status before coding; APCA and broad picker work are not commercial gates |
| Notes, outlines, advanced gradients | Notes task lists shipped in 2.6; other edge cases need current repros | Regression inventory; fix only a reproducible core-flow blocker; FEAT-033 stays later |
| Rich text | Current model already has rich-text runs; remaining phase work is narrower | Do not schedule a wholesale rich-text subsystem from the report's summary |
| ≥1% intent / 50 presales | Report labels these planning gates; denominators and sample sizes were inconsistent | Use explicit cohorts and counts below; 50 purchases is a stretch milestone, not a launch prerequisite |
| $0–500 / six weeks | Excludes substantial owner labor and possibly legal/provider costs | Cap experimental spend separately; preserve contingency and quality gates |

The report's broad P1 list is not one medium task. Finishing every import/effect,
APCA, gradient and token wish alongside commerce would make the launch date fiction.

## Calendar and capacity

Four owner work blocks/week: two 3-hour build/review blocks, one 3-hour test or
interview block, one 3-hour marketing/admin block, plus up to 3 hours contingency.
Use 12 planned hours; leave 3 for surprises. Agent effort is not an owner-hours
estimate. If owner verification queues up, finish that queue before more model work.

| Dates in 2026 | Work and responsible person | Evidence due |
|---|---|---|
| Oct 19–23 | Codex: font remediation, baseline inventory and policy drafts. Owner: compare chrome, select seller details, identify 10–20 possible partners. Marketing friend: audience/message review | No restricted font files in new built bundle; existing documents/settings intact; actual data-flow map; private recruitment list |
| Oct 26–30 | Codex: durable Pro-interest form, separate consents and minimal telemetry. Owner: test live flows after deployment authorization; run 5 first-use sessions | Consent-off network check; records survive provider failure/retry; confirmed receipt/unsubscribe; first observed task results |
| Nov 2–6 | Owner: reach 10–20 eligible partner attempts, including assisted-tech users where possible; show both price models. Codex: fix observed first-run/AT blockers | Cohort counts, failures, assisted/unassisted distinction; Nov 6 offer/scope decision |
| Nov 9–13 | Codex: one bounded fidelity slice if admitted; licensing/checkout sandbox only for selected offer. Owner: sequential acceptance, core-task VoiceOver/FKA and real Figma pass | Core-loop evidence; offer terms and exact deliverable; purchase/refund/revocation/restore sandbox receipts or explicitly interest-only status |
| Mon Nov 16 | Codex + owner: v2.7 release candidate review | All mandatory gates green, or a written reduced scope and revised date; no waiver by deadline |
| Nov 17–20 | Codex: regression freeze, signed archive, notarization/package preparation. Owner: upgrade/relaunch and final legal/copy review; publication only after authorization | v2.6→v2.7 continuity; new archive/ZIP receipts; release target Fri Nov 20 if gates pass |
| Nov 23–27 | Buffer for fixes and campaign prep; US Thanksgiving week is deliberately quiet | Approved final demo, captions, image descriptions, channel drafts and support coverage |
| Tue Dec 1 | Owner + friends: public campaign after go/no-go. Codex: support triage and measurement checks | One canonical destination; community post, short demo, collaborator shares; paid CTA only if paid gates passed |
| Dec 8 and Dec 15 | Owner + Codex: campaign and first 14-day cohort review | Correct denominators, raw counts, source quality, net receipts/refunds, support hours; revise message once if needed |
| Jan 14, 2027 | 90-day review (90 days after Oct 16) | Retention of matured cohorts, paid demand, cash after fees/refunds, owner workload; choose next small scope |

Nov 20 is the release target; Dec 1 is the campaign target. The campaign does not
need a second application release if v2.7 is already stable. If payments are not
ready, Dec 1 can invite **Pro interest** without claiming Pro is purchasable.
If core safety, privacy or accessibility gates fail, move the campaign as well.

## Dependency ordered implementation cards

Each card ends with a receipt or an owner decision. New files named below are
proposed seams; existing paths were inspected. Do not implement every card in one
unreviewable change. A date is never evidence of completion.

### 1 Font and distribution hygiene — Oct 19–23

Codex removes `EXP [design]/UI/FontRegistration.swift` and owns `UI/DesignTokens.swift`,
`EXP__design_App.swift`, `Resources/Fonts/` and build-resource inspection.
Start with native system font resolution without embedding downloadable SF files;
compare the existing condensed-layer treatment. If it loses needed density,
select an OFL face with the owner, include its exact license and verify metrics.
Remove forbidden resources from app, design export and website-distributed assets
where present; inventory first, preserve old immutable releases.

Acceptance: new built/shipping bundle has no SF Compact font binaries, readable
layer rows in light/dark/Large interface type, no clipped names or changed document
font records, existing document round trip, build and appearance check pass.
Owner approves visible typography. No historical release ZIP is rewritten.

### 2 Durable signup and policies — Oct 19–30

October 16 early foundation: INFRA-005 is locally checked. Resume from
[`launch/DATA-FLOW-AND-SIGNUP-v2.7.md`](launch/DATA-FLOW-AND-SIGNUP-v2.7.md)
for actual data inventory, setup compatibility and dated remaining steps.
Full Pro/confirmation/privacy gates remain pending.

Codex owns `api/signup.js`, `website/src/App.jsx` (`SignupForm`, `DownloadSignup`),
site routes/footer, and drafts under `docs/launch/`. Audit Resend configuration
without exposing secrets. Reuse provider support where it meets the requirements;
select storage before implementation rather than adding a database by reflex.

Use distinct release-list, Pro-interest and optional marketing purposes. Store
normalized email, consent version/time, purpose, proposed price/model, source
allowlist and confirmation state. Deduplicate submissions and distinguish an
existing signup from failure. A successful notification email is not proof of a
saved contact. Require durable write before claiming signup success; protect from
abuse and avoid logging emails/provider payloads unnecessarily. Confirmation
mail delivery/unsubscribe need real owner/provider evidence, not mocked HTTP 200s.
Do not subscribe the existing release list to marketing automatically.

Draft privacy/EULA/refund/support/third-party notices against actual behavior:
local files, Sparkle, Figma API, Sanaa's client/provider, website hosting/logs,
email signup, opt-in analytics and prospective checkout. Owner confirms legal
seller/contact, refund term, geography and ownership; qualified review resolves
jurisdiction-specific questions. MoR tax services do not settle all seller duties.
Public repository licensing is a conscious owner decision; do not apply an open
source license or privatize it as housekeeping. Inventory third-party assets and
AI-assisted provenance; an assignment is relevant only to the actual owner/seller.

Acceptance: success/error/duplicate/retry paths, confirmed persistent record,
separate unchecked permissions, working unsubscribe/deletion request, policy
links and no misleading download/list success message. Backend secrets stay server-side.

### 2a Free member hub — target selected Oct 16, staged before billing

The owner wants profile/preferences, feedback and beta participation, Pro interest,
community profiles, news/updates, private support tickets/replies, an eventual
Discord link and voluntary developer support. Forums are later. FEAT-069 records
this web-hub target; it does not make every area a native v2.7 release gate.

Read [`launch/ACCOUNTS-AND-PRIVACY-v2.7.md`](launch/ACCOUNTS-AND-PRIVACY-v2.7.md)
for exact areas/permissions and conditional dates: Oct 19–23 shared privacy/hosting;
Oct 26–30 auth/profile/preferences; Nov 2–6 community/news and ticket design;
Nov 9–13 private ticket workflow; Nov 16–20 hosted/lifecycle/AT verification.
Move hub dates when gates fail, while protecting core app release/campaign checks.
No account auth or ticket system is claimed implemented by this plan.

Account creation does not subscribe people to email purposes or turn on analytics.
Accounts, confirmed Pro interest, app activation and payments use distinct counts.
Keep editing/exports/download and voluntary support account-free. The standalone
support page and fresh-email-confirmed live Pro-record erasure are implemented
locally (INFRA-008/007); actual hosted proof remains pending.

### 3 Consent and measurement — Oct 26–30

Codex proposes a small app `UsageMetrics` service, wired through app startup,
Settings and successful import/export/handoff boundaries in `ExpDocument.swift`,
`ExportPanels.swift`, `HandoffPackageWriter.swift` and `HandoffPanel.swift` after
tracing the actual completion routes. Instrument successful completion, not
button taps, cancelled dialogs or failed file writes.

Default off. One plain opt-in explanation, persistent setting, withdrawal stops
upload and clears queued events/identifier; no repeated consent nag. Do not enqueue
pre-consent activity. Bound queue/retries and retention; network failure cannot
block drawing, saving or export. Use a random app-install identifier only with
consent, a temporary in-memory document token for loop pairing, coarse app/OS
version and fixed enumerations. No filenames, paths, URLs, emails, text, images,
prompts, tokens, document IDs, raw error strings or hardware fingerprint.

Choose the endpoint/vendor and actual retention before shipping; proposed maximum
30 days of raw events, then aggregates for at most 12 months. Verify hosted logs and provider settings
match policy. Analytics, marketing signup and license verification have separate
purposes and controls; purchased software still works with analytics off.

| Event | Meaning and allowed dimensions |
|---|---|
| `eligible_first_run` | First consented usable app session; app version, coarse OS, consent/schema version |
| `work_started` | New or successfully imported work; fixed source family only |
| `work_edited` | First successful user edit in that temporary work session; no edit contents |
| `output_completed` | Successful export/handoff write of that edited work; fixed output family |
| `activation_completed` | Derived once per consented install after the above loop in one work session within the first 7 days |
| `active_day` | One per consented install/day with meaningful editing; not foreground alone |
| `pro_interest_confirmed` | Separate backend signup count; model/price/source; no email in analytics |

Website events: qualified landing, download outbound click, offer view, confirmed
interest and checkout start if available. A GitHub outbound click is **not** a
verified download/install. Keep website and app cohorts separate; do not silently
join them by email, IP or fingerprint. Exclude internal traffic/test orders.

Acceptance: captured traffic proves no analytics before consent/after withdrawal;
allowlist scrub, dedup/relaunch, failed-write/cancel exclusion, offline behavior
and provider retention verified. Opt-in bias and coverage appear in every report.

### 4 Real first use and accessibility — Oct 26–Nov 13

Owner recruits with authorized personal outreach; Codex prepares a 20-minute script
and two small owned fixtures. Include independent designers, design developers
and accessibility/design-system practitioners with eligible macOS 26.2+ machines.
Do not substitute friends liking the idea for independent task attempts.

Task: install/open, create or import, edit text/shape, assign relevant meaning,
save/reopen and export/handoff; inspect the output. Observe first, then assist and
record exactly when. Ask whether the output would replace any step in their work.
For Sanaa, disclose user's own compatible agent tooling/account and external
provider behavior; AI is optional and not required to complete the core task.

Owner runs VoiceOver and Full Keyboard Access across install/first run, file
open/save, tools/layers, text entry, inspector, contrast/roles, handoff, consent
and any license surfaces. Record environment, task, result and issue. Include
light/dark, Increase Contrast, Reduce Motion/Transparency and Large interface
text; reuse `ACCESSIBILITY-CONTROL-AUDIT.md`, do not claim whole-app coverage from
one path. Consult official Apple/W3C specs for touched semantics before coding.

Gate: no blocker that prevents the marketed core task; material AT failures fixed
and retested. Any remaining limitations are precisely recorded. Formal compliance,
certification and universal accessibility claims remain out of marketing copy.

### 5 Offer decision and license lifecycle — decision Nov 6

Use the same **candidate** Pro benefit in both price cards so the pricing model is
the variable. Candidate benefit to test: reusable, batch handoff/export workflows
for repeated delivery. It is not built or committed; prototype the workflow on
paper before adding it. Semantic handoff, basic export and current features stay
free. Alternatively test a clearly labeled supporter purchase; never disguise a
donation as an unlock. Discard an offer nobody can explain or wants.

Balanced card order across 10–20 users: A **$89 one-time, one year of updates,
continued use of eligible versions**; B **$8/month or $79/year**, only if the
recurring benefit and cancellation behavior make sense. Record preference,
expected use, fairness, price objections and what would make them purchase.
These are research anchors, not final prices. At least 3 specific interested
users and a coherent, deliverable benefit justify a bounded paid-slice spec;
this is directional evidence, not statistical validation.

Select by Nov 6: benefit, one pricing model, free boundary, education/hardship
terms, device policy, refunds and update entitlement. New paid feature must fit a
3–5 agent-workday implementation cap plus owner verification by Nov 13; otherwise
ship readiness + interest, and schedule paid functionality after proof. Do not
invent an unavailable Studio tier or price annual renewals before the policy.

Lemon Squeezy is a provisional shortlist leader for built-in license APIs; compare
actual eligibility, fees and renewal/version needs with Paddle before owner signs
up. Use sandbox checkout/fulfillment first. App receives a signed entitlement;
provider secrets never ship in the app. Keychain for credentials as appropriate,
server-side signed webhook validation, idempotent order handling and supportable
license restore. Never rely on appcast display dates alone for paid entitlements.

For one-time licenses, encode an immutable updates-through date and release
eligibility in signed data. Preserve access to previously eligible versions;
expired update coverage must not erase, lock or downgrade the user's work.
Prevent installation of an ineligible paid update with a clear choice and a
recoverable prior version. Free/security fixes need an explicit eligibility policy.
Subscription cancellation/refunds/revocation and offline grace must be defined
before sale. No mandatory always-online launch gate for the local editor.

Acceptance: checkout→verified webhook→receipt/key→activate→relaunch→offline use;
restore on second machine within policy; duplicate/out-of-order webhook,
refund/revoke, expired updates, unavailable license server and old-version
recovery. Real live purchase and refund wait for explicit owner authorization.

### 6 Fidelity triage and freeze — Nov 2–20

Codex reproduces report items against current source; owner supplies permitted
real Figma/demo files. Save/reopen, export and re-import are separate checks.
SVG candidate is local `<clipPath>` to existing editable shape masks with simple
supported geometry and explicit unsupported-case reports; nested clips,
objectBoundingBox, CSS `mask-image` and general mask modes require separate scope.
Cap at 2–3 agent-workdays plus owner test. If it exceeds the cap, keep the limitation
visible and move it after launch. It is not an unconditional paid-launch blocker.

Background blur, outline/underline and BUG-055: current fixture + observed result
+ output-specific disclosure or bounded fix. A report about an intentional omission
is acceptable only when the user sees it before relying on output. A silent core
data-loss defect blocks release. BUG-034 Stage 2 remains parked. FEAT-057/059/060,
FEAT-033, APCA, full token tooling and broad typography stay post-launch candidates.

Run focused checks per change, then the established release battery at freeze;
record real fixtures and commands in the release checklist. Preserve v2.6 and
historical feed entries. The final gate is a real v2.6→v2.7 install/relaunch with
settings, recent docs, security-scoped access and document contents retained.

## Measurement and decisions

| Question | Denominator and time window | Decision |
|---|---|---|
| Can first-time partners complete the job? | All eligible attempted partner tasks, assisted/unassisted shown separately; 7 days to complete | Target ≥30% unassisted (3/10 or 6/20); <20% means fix observed friction; 20–29% iterate/retest; always inspect failures |
| Does the consented app cohort activate? | Unique eligible first runs with analytics consent and full 7-day follow-up | Same directional target; show consent coverage; never extrapolate to all installs |
| Is the priced offer interesting? | Confirmed unique interest / qualified consented offer visitors during a 14-day test; source + offer version | Seek ≥1%; below 0.3% triggers one message revision only after ≥300 measured visitors and task interviews; otherwise insufficient evidence |
| Are buyers willing to pay? | Completed orders minus refunds/test orders; actual price/model and acquisition source | First 5–10 independent purchases justify learning/support; 50 purchases is a stretch validation milestone, not a prerequisite for opening checkout |
| Do people return? | Activated consented cohort mature enough for days 8–14; meaningful edit on any of those days | Report raw count and fraction; no invented benchmark. Under 10 mature users is exploratory; ask what they returned to do |
| Is it sustainable? | Monthly net cash after payment fees, refunds and direct costs; owner support hours logged weekly | Work toward report's $2.5k/month candidate with ≤5 support hours/week; Jan review chooses an owner-defined income target, not a premature failure verdict |

Website visitors cannot be called "activated" without a voluntary supported link;
use separate populations. Report numerator/denominator, dates, exclusions and
unknowns. For example 3/300 is a noisy 1% signal, not product-market fit. Consent-off
users can participate in voluntary interviews without being covertly measured.

At a simplified 5% + $0.50 transaction fee, $89 nets $84.05 **before** extras,
refunds, tax/payout differences, costs and labor: ~$30k takes 357 such purchases.
A 50-unit test nets ~$4,202.50 under that assumption; it does not establish a
recurring $2.5k/month business. Subscription math must include churn, discounts
and support. Verify provider-specific fees before publishing economics.

## Budget and operating rhythm

Planning cap: **$500 in discretionary experiment spend**, subject to owner approval;
$0–200 newsletter placement only after gates, up to $100 participant thanks,
up to $100 analytics/email/storage contingency, $100 reserve. These are allocations,
not quotes; use existing tooling first. Legal/accounting review, entity changes,
trademark work and payment fees are outside this cap and need real quotes. Do not
carry forward the report's $0–100 legal-hygiene estimate as a vetted budget.

Monday: choose one implementation card and the week's owner test. Friday:
30-minute evidence review, update ROADMAP, triage blockers and book next interviews.
Marketing friends can own editing/calendar/channel fit; owner owns product claims,
price, public approval and the two campaign support windows. Keep private contact,
license and analytics records out of this public source repository.

## Immediate next session

1. Owner verifies INFRA-004 long/selected layer labels in light/dark, Large
   interface type, source editor and multi-window. Source/build checks pass Oct 16.
2. Inspect the new signed archive at freeze; no shipping artifact has changed yet.
3. Prepare data map and policy drafts, then durable signup; no second model slice.
4. By Oct 23, record unresolved seller/offer choices, partner recruitment status and
   actual hours. Rebaseline dates if capacity differs; keep acceptance gates intact.
