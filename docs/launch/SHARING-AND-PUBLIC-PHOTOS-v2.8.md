# Sharing kit, social previews and chosen public photos

Owner-selected October 21, 2026. Website only. No native version/release changes.

## Editing and sharing

`website/content/share-kit.html` is the single ordinary-HTML source for `/share`.
Edit words, add snippet paragraphs/buttons, download cards and claim rows there;
`website/README.md` documents the exact edit/build workflow. Build-time wrapper,
social metadata and deterministic PNG graphics: `website/scripts/build-share-kit.mjs`.
No CMS, login, tracking, commission or reward is required. Real app screenshots
and the existing logo remain downloadable. Copy is an enhancement over selectable
text. The public page and its downloads remain usable with JavaScript disabled.
Footer and public/member Share EXP controls link to the kit. Production and local
preview route `/share` and `/share/` to the static generated document.

The main HTML now contains absolute Open Graph and Twitter large-image tags,
image dimensions/type/alt and public site URL; crawlers need no React execution.
The kit has its own title/canonical URL. The social graphic URL has no account or
referral identity. This is metadata/artwork verification, not a claim that live
networks have crawled or refreshed their caches.

Copy follows the owner's supplied casual writing and distinction between tools
that support accessibility and a promise of automatic compliance. No legal or
WCAG certification is offered. Shipped features are separated from planned Pro,
sync and multiplayer work. Gravatar is deferred: its email-derived identifier and
third-party requests need an explicit member choice/privacy design. No email hash
or external photo request was added.

## Public photo data contract

Existing private uploads still live in `exp_member_user.image`. They are never
joined into the public projection. Community form choices: keep saved draft photo,
use a copy of the private photo, upload a different public photo, or no public photo.
Copying reads only the authenticated owner's current image on the server; it is a
snapshot, not a live link. Private image edits/removal do not change it afterward.

The shared browser preparer accepts PNG/JPEG/WebP ≤5 MiB, centered crop to 256×256;
only its small WebP is submitted after Save and preview. The server independently
checks canonical encoding, magic bytes, format, page count, 96 KiB input, ≤1,048,576
decoded pixels, then strips metadata/re-encodes a 256×256 WebP, ≤64 KiB. External
URLs/SVG/identity fields fail closed. Auth, origin and abuse boundaries are retained.
Community mutations use the existing owner row lock and quota. A failed save keeps
input for retry. Photo changes invalidate the shown publication preview/consent.

Migration `012_community_photos.sql` adds nullable `draft_photo` and
`published_photo` to the private community table. The existing table-level runtime
grants cover both (companion grants file documents this; no new grant needed).
Unchanged requests preserve a draft photo. Each changed draft gets a new revision.
Only the existing explicit revision-confirmed publication copies draft → public.
Only the published photo is projected publicly. Unpublish clears the published
photo; drafts stay private. Account deletion cascades the row and its images.
Reports can retain a private snapshot of the published photo for moderation, as
with other published fields; unpublish cannot recall downloaded/copied material.
Backups, provider logs and restore erasure retain their existing operating gates.

Before migration 012, the API returns `photoEnabled:false`; text saves/publications
continue and a submitted photo fails closed. No automatic old-profile publication
or private-photo migration occurs.

## Deployment handoff

1. Review source/copy/images; apply additive migration 012 to the verified existing
   account database using the operator process. Preserve existing flags and grants.
2. Deploy reviewed source using the existing install/build commands. No new flag,
   credential, storage bucket or external service is needed.
3. With disposable hosted accounts verify all four photo choices, saved preview,
   independent private edits, explicit publication, anonymous view, removal,
   moderation/unpublish and deletion. Do not publish the owner's draft for testing.
4. Check raw production HTML and both image URLs, then real social previews/cache
   refresh on desired networks. The local preview is not hosted enablement proof.

No deployment, hosted migration, push, commit, public profile publication or
external message is authorized/performed by this source task.

## Standards and integration references checked

- W3C table header/caption semantics: https://www.w3.org/WAI/tutorials/tables/two-headers/
- W3C form notifications: https://www.w3.org/WAI/tutorials/forms/notifications/
- WAI-ARIA 1.2 named region/status: https://www.w3.org/TR/wai-aria-1.2/#region
  and https://www.w3.org/TR/wai-aria-1.2/#status
- ARIA in HTML/native semantics: https://www.w3.org/TR/html-aria/
- Native radio fieldsets/legends: https://www.w3.org/WAI/tutorials/forms/grouping/
- Gravatar identifiers/requests: https://docs.gravatar.com/sdk/images/

## Fresh local evidence — October 21

- Full `npm test`: 169 service cases pass (117 accounts), plus native usage-consent/
  transport regressions. Log: `/tmp/exp-share-all-tests.log`.
- `npm run test:a11y -- --web-only`: 257 selected checks pass, 0 failed/blocked;
  154 incomplete/manual-review entries retained. Report:
  `output/a11y/2026-10-21T13-56-10-745Z/report.md`.
- Website production build, backlog IDs and `git diff --check` pass. The actual
  Vite preview serves static `/share` with HTTP 200. Desktop dark/mobile light
  captures and both graphics inspected. Test coverage includes disabled JS,
  download destinations, raw HTML metadata, copy fallback, native keyboard radio
  navigation, public-photo draft/public independence and removal.
- Failed earlier browser receipts at `2026-10-21T13-51-59-523Z` and
  `2026-10-21T13-53-59-222Z` are retained. Corrected test assumptions about native
  radio focus/wrapping and an asynchronous beta feedback focus transition; the
  entire four-variant run then passed. CLI browser caches were unavailable;
  the repository-pinned browser engines supplied the successful runtime checks.

No result certifies complete WCAG/VoiceOver usability, hosted photo operations
or real-network social-preview caching. Local disposable accounts/mail only.
