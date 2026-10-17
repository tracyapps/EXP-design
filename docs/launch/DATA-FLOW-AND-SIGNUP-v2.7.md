# v2.7 data flows and release-signup handoff

Internal implementation inventory, October 16, 2026. This is evidence for the
privacy/consent work in [the launch plan](../SELF-LAUNCH-PLAN-v2.7.md), not a
published privacy policy. Source inspection and local tests do not establish
provider configuration, retention settings, delivery or legal sufficiency.

## Tonight's completed slice

`api/signup.js` now requires contact storage and explicit release segment/topic
configuration before accepting a signup. A saved contact precedes success;
notification to the owner is optional and cannot establish list membership.
Existing contacts are read without writes: success requires an active global
subscription, the release topic opted in, and release segment membership.
An opted-out or unrelated existing contact is left alone. A conflict response is
re-read and verified; conflict alone is not success. Missing membership beyond
the first 100 results fails closed rather than guessing. No preference changes,
confirmation email, Pro enrollment or marketing enrollment are implemented here.

The browser also requires JSON `ok: true` before showing success or redirecting.
The public GitHub Releases link remains usable independently of signup.

New records store normalized email and these text properties:

| Field | Meaning |
| --- | --- |
| `source` | Server allowlist: `download page` or legacy `expdesign.app` |
| `signed_up_at` | Server UTC timestamp of this first signup request |
| `signup_purpose` | Fixed `release_updates`; other purposes rejected |
| `consent_version` | `release-updates-v1`, existing build/release notice wording |

These fields record a form request, **not verified mailbox ownership**. Existing
contacts' timestamps and permissions are not rewritten. Current form permission
covers build/release notifications only. A later Pro offer needs its own explicit
permission, proposed offer version/model/price and confirmation state.

Each provider call has a five-second timeout. Failures and throttling return a
retryable generic error without addresses, secrets, provider payloads or exception
messages in application logs. There is no automatic retry or durable notification
queue. The honeypot remains; it is not sufficient rate limiting.

## Observed flows

| Trigger and source | Data and recipient | Storage/control observed | Remaining evidence |
| --- | --- | --- | --- |
| Create/open/save/export (`ExpDocument`, AppKit panels) | Design content and assets written to user-selected local files | Local document/editor workflow; user may choose iCloud/Dropbox-backed locations | Do not promise that user-selected synced folders are local-only; inspect sensitive fixtures before sharing |
| Website visit (`website/index.html`, `vercel.json`) | Browser requests to site/Vercel; icon CSS/fonts to **unpkg.com** | Icons load without a signup or analytics opt-in | Confirm hosting/access-log retention, regions, CDN request details; decide whether to self-host licensed icons before privacy copy |
| Release signup (`api/signup.js`, `SignupForm`) | Email and allowlisted source to Vercel Function and Resend; optional plain-text email to owner's mailbox | Resend contact with release segment/topic and request properties; no browser storage added by this slice | Check real contact properties/topic defaults, provider logs/retention, unsubscribe, deletion, permissions and abuse controls |
| Download/update (`Info.plist`, `UpdaterController.swift`, appcast) | Appcast requests to `expdesign.app`; release files hosted on GitHub; request metadata such as IP/User-Agent at receiving services | Sparkle asks permission for automatic checks; manual checks available; archive signature validation | Capture actual traffic and request fields; verify preference-off behavior and profile settings; do not count requests as activation |
| Figma import (`CanvasView.swift`, `Model/FigmaImporter.swift`) | User-entered file key/token to Figma API; design JSON and image URLs returned; image fetches to returned storage/CDN origins | Token collected in memory; request header attached for `api.figma.com`; no token persistence added here | Verify redirects/logs and real account permissions; do not label this fully offline or claim a complete credential audit |
| Sanaa / connected agent (`UI/SanaaRuntimeClient.swift`, `sanaa-runtime/main.swift`, `CodexAdapter.swift`) | Prompts and allowed design tool results can reach the connected agent/provider | Bundled helper; isolated Sanaa host state; existing Codex auth referenced by symlink; per-document tool permissions; conversation deletion command exists | Confirm actual provider/account terms, traffic, conversation deletion scope and retention; deleting local state does not prove provider deletion |
| Feedback (`UI/Feedback.swift`) | User-written title/detail plus app/OS/tool/selection/document counts placed in a GitHub issue URL | User reviews and chooses to open/submit; not an automatic private support channel | URL data reaches GitHub/browser history before issue publication; warn against confidential content in the final support flow |
| Diagnostics (`UI/DiagnosticLog.swift`, canvas report action) | Machine/app info, selected document statistics/geometry and log tail in a saved report | User-selected report file; local rotating daily log keeps newest five files | Inspect actual report for sensitive names/paths before sending; no automatic upload proved by these sources |
| Planned usage measurement | Fixed events/coarse versions and consented install identifier only | **Not implemented**; must default off, exclude content/paths/URLs/email/prompts and clear queue on withdrawal | Source + captured-network consent-off/withdrawal proof before launch |
| Pro-interest discovery / planned payment/license | Email, preference, permission timestamps and hashed tokens in private PostgreSQL; confirmation mail through Resend | **Pro request/confirm/withdraw implemented locally**, enrollment disabled by default; no release-list enrollment; paid offer/checkout/entitlements still unimplemented | See `PRO-INTEREST-v2.7.md` for real local DB/browser proof and hosted/provider/legal/abuse gates; owner offer gate Nov 6 |

This is a bounded inventory of inspected entry points, not a claim that every
network path or every bundled third-party dependency has been audited. Inspect
HTML/package resource behavior and the provider-neutral MCP transport in the next
privacy pass. No analytics collection was added tonight.

## Provider setup before deployment

See [website deployment](../../website/DEPLOYMENT.md). Reuse the existing Resend
account. No new database/integration/account is required for this slice.

1. In a non-production test configuration, confirm the API key can read/create
   contacts, read topic/segment membership and optionally send owner notices.
2. Provision/verify the string properties above in Resend. Keep existing `source`
   and `signed_up_at` definitions compatible. Unknown properties must fail, not
   silently drop consent evidence.
3. Configure a dedicated release segment and release topic. Review **all topic
   defaults**: Pro/marketing must default out and cannot inherit release permission.
   Use release segment **and** release topic on release broadcasts.
4. Review existing contacts privately; do not mass-enroll or resubscribe them.
   The endpoint deliberately refuses unrelated/opted-out contacts until a verified
   confirmation/preferences flow exists. If legacy membership is incomplete,
   resolve it from actual consent evidence, not from presence in the address book.
5. Prove concurrent-create behavior against the actual provider. The read-then-create
   sequence is not a transaction. It omits global `unsubscribed`, but topic behavior
   during a concurrent opt-out/upsert still needs hosted proof or a stronger
   confirmation/storage design. Do not advertise race-proof preference preservation.
6. Check provider rate limits under realistic retries/concurrency; local mocks do
   not prove throughput. Configure hosting rate limiting before public promotion.
   A provider 429 is surfaced as failure rather than reported as a saved signup.
7. Review provider logs, owner's mailbox copies, retention and deletion together.
   Contact deletion alone does not remove historical mail or provider/hosting logs.

No credentials were read or changed, contacts created, emails sent or deployments
made during local verification. Deploying without the required storage/topic/
segment configuration now returns 503 rather than pretending enrollment succeeded.

## Next work, with dates and owners

| Target | Owner | Concrete completion evidence |
| --- | --- | --- |
| Oct 19 | Codex | Design the mailbox confirmation/preferences flow and separate Pro-interest contract; retain release-only legacy permission; decide whether Resend alone meets confirmation/storage needs |
| Oct 20–21 | Owner + Codex | Authorized test-address receipt: new signup, repeat, opted-out repeat, timeout/retry/concurrent create, received confirmation, unsubscribe and deletion; sanitized receipts only |
| Oct 21 | Owner | Choose private legal seller/contact and support identity; confirm any existing list consent evidence and actual hosting/email settings |
| Oct 22–23 | Codex | Policy drafts grounded in this inventory and selected provider settings; separate release and Pro-purpose controls; qualified review where needed |
| Oct 26–30 | Codex + owner | Implement/verify default-off analytics from launch card 3 after event/schema review; owner first-use/AT gates remain separate |
| Nov 6 | Owner | Compare one-time and subscription feedback for the same proposed benefit; choose a defensible offer or keep Pro interest-only |

Before publication, policy copy must state actual seller/contact, purposes,
recipients, retention, rights/deletion route, international processing where
applicable, optional provider connections and update behavior. EULA/refund/support
terms wait for the actual offer and seller decisions. Do not substitute guessed
legal details or claim product compliance from this inventory.

## Local verification

- `node --test tests/signup.test.mjs`: 15 checks, including disabled/failed storage,
  malformed input, durable-before-notification ordering, active duplicate,
  global/topic opt-out, conflict verification, network/provider errors, routing,
  missing membership, throttling, notification retry and redacted logs.
- Baseline reproduced false success with storage disabled and a null-body crash.
- Website production build succeeds; browser acceptance receipt recorded in
  `RELEASE-CHECKLIST-v2.7.md` after execution.
- No live delivery, unsubscribe, confirmation, deletion or provider race claim.

## Primary API references consulted October 16

[Create contact](https://resend.com/docs/api-reference/contacts/create-contact),
[retrieve contact](https://resend.com/docs/api-reference/contacts/get-contact),
[retrieve topic subscriptions](https://resend.com/docs/api-reference/contacts/get-contact-topics),
[list contact segments](https://resend.com/docs/api-reference/contacts/list-contact-segments),
[topic defaults and global subscription behavior](https://resend.com/blog/unsubscribe-topics).
These specify the interfaces used; they do not replace verification of this
account's settings or undocumented concurrent create/upsert behavior.

Follow-up: [Pro-interest implementation and setup](PRO-INTEREST-v2.7.md) adds a
separate PostgreSQL confirmation ledger. The release-list behavior above remains
unchanged. Its local completion does not establish the hosted confirmation gates.
