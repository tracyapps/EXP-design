# Optional native usage measurement — INFRA-010

October 17, 2026. Local implementation for v2.7/18. **Production collection is
disabled.** No endpoint is configured in the app; `/api/usage` rejects intake
unless both enablement and host-verification switches are set. No deployment,
hosted database, provider settings or public policy was changed.

## What this slice measures

The optional Settings → Privacy control defaults off. Turning it off cancels the
scheduled upload, clears the local queue and installation identifier, and forgets
in-memory work sessions. Consent is independent of accounts, marketing and Pro.
No reminder prompt or automatic enrollment exists. Previously received server
records expire separately; withdrawal does not claim to recall a received request.

The ordinary build explains why sharing is unavailable. A DEBUG-only mode is
available solely to the re-identified native UI fixture, with no network transport
or outgoing-network entitlement. It is not a production analytics preview switch.

| Event | Completion rule |
| --- | --- |
| `eligible_first_run` | Once when this installation explicitly starts a new consent episode |
| `work_started` | A usable new/open editor or a successfully committed import; fixed source family |
| `work_edited` | First subsequent committed edit in that in-memory work session; import alone is not an edit |
| `output_completed` | Edited work successfully exported/handed off; once per output family per session |
| `activation_completed` | Once per consented installation: new/import → subsequent edit → completed output in the same work session within 7 days of consent |
| `active_day` | Once per UTC day with a committed edit; foreground/selection/pan alone do not count |

A document open before consent/relaunch is classified as existing work when first
observed; its earlier creation/import/edit history is never reconstructed.
Opening an existing file can contribute editing/return evidence but cannot itself
satisfy the new/import activation gate. Undo/redo is excluded. Session pairing is
entirely in memory through weak object references; no document token or UUID leaves
the app. The document model/file format and rendering generation are unchanged.

Sources: `new`, `opened`, `svg`, `image`, `pdf`, `xd`, `figma`, `html`, `codepen`,
`storybook`. Outputs: `png`, `jpg`, `pdf`, `svg`, `batch`, `handoff`, `html`,
`tokens`, `codepen_launcher`. CodePen means a written/opened local review launcher,
not a Pen published or received by CodePen.

**Native `.design` Save/Auto Save is uninstrumented.** SwiftUI's `fileWrapper`
prepares a representation; it is not a disk-write completion receipt. Standard
Close/Save/Save As/Duplicate/Revert behavior was preserved. Native save measurement
needs a separately verified completion seam. Website events are also outside this
slice; a download-link click must never be reported as an install.

Visual exports now propagate render/write failure, display an error and remember
export choices only after success. A partial multi-file export is not counted as
a completed batch. Handoff/HTML/tokens callbacks follow the final successful write.

## Wire/data contract

`POST /api/usage`, JSON, no browser Origin/CORS, cookies or authentication.
A batch contains exactly `schemaVersion: 1`, `consentVersion: "usage-v1"`,
random UUIDv4 `installID`, and 1–32 `events`. An event contains a fresh UUIDv4 `id`,
`name`, UTC `day`, numeric major.minor `appVersion`, integer `osMajor`, plus only
its applicable fixed `source`/`output` enums. Unknown fields reject the entire batch.
No filenames, paths, URLs, emails, text, images, prompts, account IDs, document IDs,
raw errors, hardware identifiers or arbitrary properties enter the API.

The random installation ID is **pseudonymous, not anonymous** and not a count of
people. Re-consent creates a new ID. The first-party HTTP host necessarily sees a
network request/IP and receipt time; hosted access logs, TLS, regions and backups
need separate verification. App transport uses an ephemeral URLSession, disables
cookies/credential storage/cache, uses a fixed user agent, refuses redirects and
has short timeouts. It never uses a shared account session.

The local queue holds at most 64 events; events older than 7 days are pruned before
upload and on next launch/activity. An app that is not running cannot erase a file
on a wall-clock deadline. Queue and dedup state survive restart; malformed/obsolete
consent fails closed and remains untouched until explicit on/off choice. Appending
and first-edit/day work are bounded; drawing/saving/export never awaits the network.
A maximum of three failed attempts drops that batch; retries back off and survive
relaunch. Delivery is best effort and can undercount. Dropped/expired queues are
not evidence of unused software.

Collector responses: 204 only after transaction commit; 400 invalid payload; 403
browser Origin; 405 other method; 415 non-JSON; 429 exhausted per-install/day budget
(256 submitted events, including retries); 503 unavailable/disabled/storage failure.
Event UUID retries and install/day milestones deduplicate atomically. The collector
is an unauthenticated measurement endpoint; its data is not attested human behavior.
The install budget does not stop an attacker rotating IDs: host edge controls are
a required enablement gate, with no IP/fingerprint added to application records.

`migrations/004_usage_metrics.sql` creates private `exp_usage_events` and
`exp_usage_limits`, with no account/email/IP/content columns or joins. Public SQL
grants are revoked. Database access is server-side only. No migration is auto-applied.
No aggregate storage is implemented in this slice.

## Hosted enablement — not yet done

1. Use a private first-party PostgreSQL database/role and owner-selected region;
   apply migration 004 through the existing operator process. Set the server-only
   `EXP_USAGE_DATABASE_URL`; never put it or a collector secret in an app bundle.
2. Configure and verify HTTPS/origin, request/body limits, edge abuse controls,
   generic error logs, actual hosting/access-log retention and backup expiry.
   Verify there is no body/IP-to-account logging or joining elsewhere in the stack.
3. Schedule `node scripts/purge_usage.mjs` **daily**, using the private DB URL.
   It removes event rows at 29 days and expired admission counters even without
   traffic, leaving a day of margin under the 30-day live-store ceiling. Retain success/failure monitoring and a real hosted expiry
   receipt. Local purge tests do not establish that the hosted job is scheduled.
4. Finalize owner-reviewed data-flow/privacy wording, contact and any operational
   deletion process; match the actual log/backup/retention settings. Do not claim
   immediate deletion of previously received events from a local toggle.
5. Only after those receipts: set `EXP_USAGE_HOST_VERIFIED=true` and
   `EXP_USAGE_ENABLED=true`. Put `EXPUsageEndpoint` in the app Info.plist as the
   verified first-party HTTPS URL ending `/api/usage` (proposed same site origin,
   `https://expdesign.app/api/usage`; not configured by this change).
6. Use a separate staging collector/database for packaged verification, keeping
   internal/test records out of launch cohorts. Capture real consent-off/on/withdraw/
   relaunch/failure traffic from the packaged app and confirm expected rows/expiry, then run owner keyboard/VoiceOver and
   appearance review. Keep shipping collection unavailable until these gates pass.

No provider/signup/account permission is implied by enabling this separate purpose.
The operator should disable the endpoint immediately if the purge/log/abuse gates
stop holding. No raw-data export or public reporting API is introduced.

## Verification

Run `npm run test:usage` (or `bash scripts/verify_usage_metrics.sh`). The runner
creates a private socket-only throwaway PostgreSQL cluster and temporary executable;
it never accepts hosted credentials or sends email. It runs 14 DB/collector tests,
Swift lifecycle/concurrency/allowlist checks, then a real loopback URLSession → HTTP
collector → PostgreSQL round trip. Exactly one collection POST/six expected rows; none before
consent/after withdrawal; no cookies/auth and no followed redirect. Logs:
`/tmp/exp-usage-services.log`. App/thumbnail/test build: `/tmp/exp-usage-build.log`. It passes with retained
Swift conformance/XCTest setup-isolation warnings; this is not a warning-free or
full Swift 6 migration claim.

**Final native run: three passes, zero failures/skips** in
`output/a11y/usage-consent-receipts-20261017/native/results.xcresult`:
consent off → on → relaunch → off; actual component edit plus cancelled/completed
handoff with one output event and no pre-consent creation inference; unavailable
collection in the normal build. Log: `/tmp/exp-usage-receipts-runtime.log`.
Cropped Privacy enabled/disabled screenshots inspected. Earlier pattern creation/
reopen regression also passes in `output/a11y/usage-consent-20261017`.
Full `npm test` passes all **77 service checks** (15 release signup, 23 interest,
25 accounts, 14 usage), plus the Swift lifecycle and actual-wire checks.
Log: `/tmp/exp-usage-services-regression.log`. Interface preference checks,
bounds/raster regression and website build pass. This is not the full app/AT/appearance matrix.

Earlier
`output/a11y/usage-consent-20261017` has numeric-checkbox/Touch-Bar query errors;
`usage-consent-final-20261017` passes real consent persistence/revocation and a
cancelled then completed handoff, but the default-off test inherited consent left
by the preceding receipt test. Cleanup now uses the real UI before the next case.
`usage-consent-confirmed-20261017` read the preference file before cfprefsd's
asynchronous flush; the expected output row was present on subsequent inspection.
The final test explicitly waits for that durable receipt before asserting counts.
These failed suite receipts are retained, not relabeled as passes.

## Reading evidence

Use consent-episode/install cohorts and raw numerator/denominator/day ranges, not
unique people or all installs. Separate source/output families. There is no covert
count of opt-out installations, so automatic consent coverage cannot be calculated;
use the separately recruited partner cohort's known attempted tasks/permissions for
coverage. Report these denominators separately. Activation is client-derived and
best effort; offline expiry, retry caps, opt-in bias and unsupported native-save-only
workflows limit inference. No revenue, signup or account linking is performed.

Primary references checked before UI/transport work:
[Apple privacy guidance](https://developer.apple.com/design/human-interface-guidelines/privacy),
[VoiceOver alternative labels](https://developer.apple.com/design/human-interface-guidelines/voiceover),
[ephemeral URLSession](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral),
[ReferenceFileDocument fileWrapper](https://developer.apple.com/documentation/swiftui/referencefiledocument/filewrapper(snapshot:configuration:)),
[standard save command group](https://developer.apple.com/documentation/swiftui/commandgroupplacement/saveitem).
The official Markdown versions were read when HTML required JavaScript. No exported
ARIA semantics or legal compliance certification was changed/claimed.
