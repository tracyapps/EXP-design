# Self-launch source checks — 2026-10-16

Bounded primary-source review supporting v2.7 planning. Sources checked October 16, 2026; vendor terms and fees need rechecking before checkout goes live. These findings correct consequential recommendations in the AutoClaw sellability report. Recommendations below are implementation judgments, not legal advice or evidence that a provider has approved EXP.

## Corrections to carry into the plan

| Report recommendation | Finding | v2.7 action |
| --- | --- | --- |
| Replace bundled SF Compact fonts | Supported by Apple's published license; affects free distribution too. | Remove bundled files/registration; use system typography or a separately verified redistributable face; inspect the signed app. |
| Rename the generated bundle ID before selling | Unsupported as a commercial requirement; creates upgrade risk. | Preserve `tapps.EXP--design-` and related target identities. Any later rename needs its own migration project. |
| Both MoRs cost about 5% + $0.50, with predictable net proceeds | Base headline rates match; Lemon Squeezy documents additional charges. | Model geography/payment mix, tax treatment, refunds and payout method explicitly. |
| License keys plus signed appcast dates enforce perpetual use + one year of updates | Requires EXP-specific entitlement rules; signatures establish authenticity, not purchase rights. | Separate purchased-use entitlement from update eligibility, and test both. |
| A dedicated LLC/IP assignment is required before taking money | A separate LLC is a business-structure decision. Assignment depends on actual ownership and who will sell. | Record seller, existing entity, chain of title and adviser decisions; do not invent a mandatory restructuring task. |
| Anonymous opt-in analytics solves the evidence gap | Consent limits collection; a persistent identifier can still be personal data. | Use a minimal event contract, explicit consent, retention/deletion rules and accurate public language. |

## Fonts: a concrete distribution blocker

Apple's SF Compact download license limits its permitted use to watchOS UI mockups, prohibits embedding in software, and restricts redistribution. Calling EXP a macOS app does not supply a permission to ship the downloaded files. [Apple Fonts, SF Compact agreement §§2A–2B](https://developer.apple.com/fonts/)

Initial source inspection confirmed five bundled weights in `EXP [design]/Resources/Fonts/LICENSE-NOTE.md`, registration in `UI/FontRegistration.swift`, and the condensed layer-label seam in `UI/DesignTokens.swift`. The pre-remediation note's reassurance about personal builds is not a distribution permission. This review did not inspect the installed/notarized v2.6 archive; inspect that artifact before stating exactly what prior binaries contain.

Recommended first slice: remove downloadable SF Compact files and launch registration; choose system font width/design APIs or verify the exact replacement font's license and notices. Check long layer names, selected weights, small labels, light/dark appearance and VoiceOver. Search both the signed app and new archive for font payloads and stale notices. Keep immutable historic release artifacts unchanged; record remediation in the next release.

## Bundle identity: preserve continuity

Apple describes the bundle ID as the app's system identity; some entitlements depend on it. Apple also creates an associated container for sandboxed apps. [Changing the bundle identifier](https://developer.apple.com/documentation/xcode/changing-the-bundle-identifier), [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

Sparkle's own maintainers state that changing a bundle ID is unsupported/untested and that the framework assumes a permanent ID. This is a historical maintainer statement, reinforced by the current installation design's use of the host bundle identifier. [Sparkle issue #1600](https://github.com/sparkle-project/Sparkle/issues/1600), [Sparkle installation design](https://github.com/sparkle-project/Sparkle/blob/2.x/Documentation/Installation.md)

Local project settings use `tapps.EXP--design-`; Sparkle service entitlements derive from `$(PRODUCT_BUNDLE_IDENTIFIER)`. The practical inference is to preserve identity for v2.7. The report provides no source showing that an unpolished identifier prevents direct commercial sales. A rename would require separate proofs for existing preferences, sandbox state, bookmarks, Keychain access, thumbnail/helper identity, document associations and v2.6→new-version update/relaunch. None of those migration proofs has been performed here.

## Checkout: shortlist with explicit lifecycle work

| Provider | Verified official capability | Consequence for EXP |
| --- | --- | --- |
| Lemon Squeezy | 5% + $0.50 base; automatic license-key generation and activation/validation/deactivation API. | Best first integration candidate for a small desktop product, subject to owner selection and store approval. |
| Paddle | 5% + $0.50 headline rate; payment/tax/billing; documented webhook-based app provisioning. | Viable alternative. Budget an EXP entitlement service or a verified licensing integration; this review did not establish native desktop license-key generation in current Paddle Billing. |

Sources: [Lemon Squeezy pricing](https://www.lemonsqueezy.com/pricing), [license generation](https://docs.lemonsqueezy.com/help/licensing/generating-license-keys), [License API](https://docs.lemonsqueezy.com/api/license-api), [Paddle pricing](https://www.paddle.com/pricing), [Paddle provisioning](https://developer.paddle.com/build/subscriptions/provision-access-webhooks/).

Lemon Squeezy documents +1.5% for international transactions, +1.5% for PayPal, and +0.5% for subscriptions. Its fee example applies the percentage to the order including tax. US bank payouts are free; other methods/regions differ. Avoid a blanket 94–95% net assumption. [Official fees](https://docs.lemonsqueezy.com/help/getting-started/fees)

Live sales require store activation, business review and identity checks. The stated typical 2–3 business days is not an approval promise; start this owner task early and gate the launch on actual approval. [Store activation](https://docs.lemonsqueezy.com/help/getting-started/activate-your-store)

Recommended acceptance contract, before accepting money:

1. Hosted checkout → verified payment → correct product/variant entitlement → receipt/key → activation → restart/offline use.
2. Validate expected store/product identity; keep administrative API credentials and webhook secrets off the shipped client.
3. Handle duplicate/out-of-order events idempotently; reconcile missed events. Authenticate webhook payloads. [Lemon Squeezy signing](https://docs.lemonsqueezy.com/help/webhooks/signing-requests), [Paddle webhooks](https://developer.paddle.com/webhooks/)
4. Demonstrate restore, device replacement/deactivation, support reset, network outage and provider outage.
5. Demonstrate full/partial refund and chargeback behavior; never treat every partial refund as a full revocation. Lemon Squeezy emits `order_refunded` for both full and partial refunds; Paddle has separate adjustment actions/statuses. [Lemon events](https://docs.lemonsqueezy.com/help/webhooks/event-types), [Paddle adjustments](https://developer.paddle.com/webhooks/adjustments/adjustment-created/)
6. If offering perpetual use plus 12 months of updates, preserve purchased-version use after the update window. An expiring license key alone does not encode that promise. Sparkle offers delegate hooks for selecting/vetoing updates, but EXP must implement and verify the policy. Manual-download behavior also needs entitlement checks. [License API status](https://docs.lemonsqueezy.com/api/license-api), [Sparkle updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)

Account requirement, price, paid features, license limits, update term, offline grace and refund terms remain owner decisions. A “Pro signup” can initially be an accurately labeled interest list; it need not force an account system into the native editor.

## Opt-in measurement without collecting design work

The FTC recommends inventorying collection, minimizing retained data and protecting what is kept. ICO guidance distinguishes pseudonymisation from anonymisation; replacing a name with a persistent ID is not automatically anonymous. [FTC app security guidance](https://www.ftc.gov/business-guidance/resources/app-developers-start-security), [ICO pseudonymisation](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-sharing/anonymisation/pseudonymisation/)

Recommended v2.7 design: collection off until an affirmative choice; equal access to decline; a persistent Settings switch; no document names, contents, layer text, paths, imported URLs, prompts, screenshots, license keys or email addresses in events. Restrict events to an allowlist such as consented session start, create/import success, export/handoff success, coarse failure category and app/OS version. Derive activation once locally from create/import → successful output; define the window and deduplication before coding. Do not retrofit events from earlier unconsented activity.

Use a resettable random identifier only if cohort measurement actually requires it. Describe the data as pseudonymous when applicable. Keep commerce/support identities separate. Choose retention (proposal: raw events 30 days, aggregate counts 12 months), removal/deletion support, server access, processor agreements and log settings before enabling ingestion. Withdrawal must stop collection, cancel queued sends and discard unsent events; deletion of already stored data needs a separate documented mechanism. Transport/CDN logs can retain IP addresses even if the event schema does not.

The policy must describe actual native telemetry, website analytics, hosting logs, Sparkle update requests, checkout/license validation, support submissions and external agent/provider connections. Avoid “nothing collected” if optional telemetry or operational requests exist. Website cookie/storage rules depend on technology and audience; native-app opt-in does not settle website compliance. ICO's guidance is under revision following UK legislation, so recheck the applicable rules rather than copying a blanket cookie-consent claim. [ICO cookies and similar technologies](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/cookies-and-similar-technologies/?q=consent)

Opt-in participants are a selected sample. Report opted-in installations, eligible participants, counts and time windows separately. GitHub stars and absent analytics do not establish that no one uses EXP. Small design-partner cohorts are qualitative usability evidence, not market-size or conversion forecasts.

## Seller, ownership and public terms

The SBA recognizes sole proprietorships and LLCs as different valid structures, with different liability/tax consequences. It does not impose a dedicated product LLC on every software seller. [SBA business structures](https://www.sba.gov/counseling/launch-your-business/)

US copyright transfers generally require a signed writing; that supports documenting a transfer when one is actually needed. It does not establish that Tracy must assign personally owned work to a newly formed entity before any sale. Confirm existing ownership, employment/client constraints, third-party licenses and intended contracting party first. [17 USC §204](https://www.copyright.gov/title17/92chap2.html)

Before charge: name the actual seller and support contact; align EULA/license grant, paid entitlement, update policy, privacy notice, refund process and third-party notices with that seller and the selected MoR. Resolve entity/IP questions with the owner's advisers where necessary. Do not add an open-source license casually: a public repository's licensing policy and an end-user license for a paid app are separate decisions. No trademark clearance, entity review, tax review or definitive legal-document review was performed in this bounded pass.

## Implementation receipt after the research pass

October 16: INFRA-004 removed five app fonts, 72 design-export SF binaries and
font registration; native system condensed width replaces the layer-label face.
Website guide contained declarations pointing to absent fonts, not payloads;
those declarations were removed. New unsigned Debug app has no OTF/TTF files.
Build/appearance/site checks and filename distribution guard pass. Owner visual
acceptance and signed-release/archive checks remain pending; historic release
artifacts are unchanged. This is remediation evidence, not a general legal audit.

## Owner typography review and current Apple guidance

October 16 follow-up: owner rejects system SF Pro condensed as harder to read
than prior SF Compact Display. These are different type designs; removal of
font files does not settle the replacement's visual suitability. No new font
was selected in this review.

Apple's current [Fonts technology overview](https://developer.apple.com/documentation/technologyoverviews/fonts)
explicitly says not to bundle fonts Apple ships or makes available, naming SF
Pro, SF Compact, SF Mono and New York. Using OS-provided fonts through supported
APIs differs from embedding downloaded files. The [download agreement](https://developer.apple.com/fonts/)
§2B expressly prohibits embedding; a free download is not a redistribution grant.

Candidate alternatives for actual small-text comparisons: [Barlow Semi Condensed](https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed)
and [Inter Tight](https://github.com/google/fonts/tree/main/ofl/intertight), both
SIL OFL distributions. Their licenses allow bundling with software subject to
the license conditions and notices; neither is yet visually tested in EXP.
