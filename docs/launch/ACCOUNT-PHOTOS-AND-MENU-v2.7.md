# Account photos, menu and explanation

October 18, 2026 · FEAT-069. Owner selects a circular account control at the
right end of the website header, photo upload and a public account explanation.
Local implementation; owner push/deployment and hosted photo review remain ahead.

October 21 follow-up: FEAT-081 adds separately chosen public photos. The original
private photo remains excluded from public reads; a member can now explicitly
copy it to a separate draft/snapshot. See `SHARING-AND-PUBLIC-PHOTOS-v2.8.md` for
migration 012, photo choices, preview/publication and current rollout gates.

## Observable behavior

- The far-right header button shows a saved photo, initials or a person icon.
  Signed-out visitors can sign in/create an account. Signed-in members can reach
  their profile, preferences, beta/feedback, Pro interest, community and tickets,
  or sign out. Download remains in primary navigation and the dropdown.
- The dropdown is a navigation disclosure with ordinary links/buttons, not an
  application menu. Enter/Space toggle; Tab reaches links; Escape closes and
  returns focus. Outside pointer/focus closes it. The trigger is at least 44×44.
- `/account/profile` supports a local centered crop preview, explicit save,
  cancel and removal. A failed save keeps the same prepared image for retry.
  Saving/removing a photo preserves unsaved private-profile text. Successful
  removal returns focus to the file control; retry focus waits for re-enabled
  controls to render, including Safari.
- `/accounts` explains the optional free account, privacy and current features.
  It identifies settings sync/Discord/community expansion as future possibilities
  without dates. It does not advertise cloud document sync or collaboration.
  Registration, email purposes, community publication and paid access remain
  separate. The editor, exports, downloads and public news remain account-free.

## Photo data contract

The browser accepts PNG/JPEG/WebP up to 5 MiB, checks decoded dimensions, previews
a centered square crop and prepares a 256×256 WebP before explicit save. Only
that small crop is sent; no original file, filename, EXIF or external image URL
is stored. The server independently checks canonical encoding, magic bytes,
format/pages, encoded size (96 KiB), decoded pixels (1,048,576 maximum), then
rotates/crops/re-encodes a 256×256 WebP with metadata stripped and a 64 KiB cap.
Sharp 0.35.5 is pinned. Invalid and animated inputs fail closed.

The bounded data URI lives in the existing private `exp_member_user.image`
column. There is no new migration, public bucket or image-provider credential.
Only a verified session can update/remove its own image; submitted identity fields
are rejected. A separate HMAC-scoped counter limits changes to 30/hour; removal
remains available. Account deletion removes the live image with the user row.
Backups/restore erasure remain a separate operating gate. The community/public
API projection excludes this photo and the private account identity.

## Shared header session

All React website pages now make one deduplicated optional `GET /api/account`
to render the requested member header. This deliberately updates the older
zero-account-request `/news` contract: the news content still reads no member
data/email ledger and renders when accounts are unavailable. Signed-out reads
create no account or cookie. The header never blocks public content/downloads.

Profile/session data stays in React memory, with no local/session storage cache.
The existing HttpOnly server cookie authorizes requests. A BroadcastChannel sends
only a `changed` signal; tabs re-read the server on changes, and visible tabs
refresh on focus after 30 seconds. Sign-out clears the shared header and other
tabs. A generation guard prevents an older request restoring cleared session
state. The dropdown respects the member's larger-account-text choice.

## Acceptance and remaining proof

Real disposable PostgreSQL tests cover own-image save/read/remove, cross-account
isolation, unauthenticated/forged requests, encoding/MIME/script/pixel/size refusal,
metadata stripping, upload quota, storage failure and account deletion. Browser
journeys exercise keyboard disclosure, photo lost-response retry, draft preservation,
reload/removal, SVG refusal, guest service outage and cross-tab sign-out across
Chromium/WebKit in dark desktop and light mobile variants.

Final `npm test`: **153 service cases passed**, plus existing native/wire checks,
exit 0 (`/tmp/exp-account-avatar-final-services.log`). Final
`npm run test:a11y -- --web-only`: **201 passed, zero failed/blocked, 128 incomplete
contrast scans / 86 distinct rule-target findings**, exit 0, at
`output/a11y/2026-10-18T05-22-57-872Z/report.md`. Photo-menu viewport screenshots
were inspected in all four variants (`web/*-profile-photo-menu.png`); the synthetic
photo is a green square cropped into a circle. `npm audit --omit=dev` reports zero
vulnerabilities. These checks do not establish physical VoiceOver,
Full Keyboard Access, all low-vision settings or complete WCAG 2.1 AA conformance.
Existing automated contrast incompletes remain review items. Hosted upload,
sign-out across actual sessions and privacy/backup policy need owner acceptance.

Earlier failed browser runs remain at `2026-10-18T05-06-14-097Z` (initials label),
`05-12-02-010Z` (test-only obsolete Sharp import path), `05-13-26-789Z`
(test-only covered mobile click), and `05-15-14-614Z` (same test click plus actual
Safari retry focus race), all under `output/a11y/`. The final run follows both
product fixes and the corrected test; earlier failures are not called passes.

Primary sources checked before implementation:
[APG disclosure navigation](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/examples/disclosure-navigation/),
[ARIA in HTML](https://www.w3.org/TR/html-aria/),
[WAI-ARIA expanded](https://www.w3.org/TR/wai-aria-1.2/#aria-expanded),
[controls](https://www.w3.org/TR/wai-aria-1.2/#aria-controls),
[WCAG focus order](https://www.w3.org/TR/WCAG21/#focus-order),
[label in name](https://www.w3.org/WAI/WCAG21/Understanding/label-in-name.html),
[OWASP file uploads](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html),
[Sharp constructor limits](https://sharp.pixelplumbing.com/api-constructor/),
[Sharp output metadata](https://sharp.pixelplumbing.com/api-output/).
