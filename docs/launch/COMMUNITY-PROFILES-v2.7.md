# Optional community profiles — FEAT-069

October 17, 2026 (America/Chicago). Initial local implementation; public rollout was disabled.
Production enabled by owner approval October 21; see the enablement receipt below.
Owner's successful hosted account creation/email-code sign-in is separate evidence
for the existing account foundation, not acceptance of this new public surface.

## Behavior and privacy contract

`/account/community` prepares an optional public profile. Nothing is copied from
the private profile automatically. Members choose a handle (3–30 lowercase ASCII
letters/numbers/hyphens), display name (80 characters), optional bio (500) and safe
HTTPS website (300, no embedded credentials). Reserved staff/system handles are
refused. Each account has at most one draft/handle reservation. The handle becomes
fixed after first publication in this version; deleting the account releases it
for possible reuse. Editing/renaming handles is a later design decision.

Save and preview creates a **private draft**. A separate unchecked publication
choice and Publish action submits the saved revision and `community-profile-v1`.
The server refuses stale revisions, missing confirmation and old wording versions.
Publication copies those four chosen public fields into a separate snapshot.
Later draft/private-profile edits cannot change the public snapshot. Same-revision
publication retries are idempotent; unpublishing clears the snapshot and keeps
the private draft. Live account deletion cascades draft, public snapshot, associated
reports and quota rows. It does not retract copies already made outside EXP.

`/people/:handle` and GET `/api/people?handle=…` expose **only** handle, chosen
display name, bio and website, through an explicit server projection. No account
UUID, email field, private biography, beta/Pro permission, feedback or report is
included. Public visitors need no account. Browser public reads omit account
cookies. User text is rendered literally; no uploads, rich HTML, avatar storage,
directory, comments or forums are introduced. Pages/API use no-store/no-referrer/
noindex for this first rollout. Those headers do not prevent people making copies.

## Reports and moderation

Signed-in, verified members can submit a private report from the public page.
The API checks identity/ownership and published target state. Report stores:
reporter/target UUIDs, target publication revision, category, reason (500), server
time and a private snapshot of the four public fields. Report retries for the same
reporter/target/publication keep the first record; a later published revision can
be reported separately. Own-profile reporting points to unpublish. Reports never
automatically hide the target, and neither reports nor reporter details appear in
public/target-owner responses. Receipt means saved, not staff review or resolution.

Reporting requires a free account; anonymous visitors get an explicit sign-in path.
There is no staff web interface or report email notification yet. Before enabling
public profiles the owner must name a moderation operator, establish their private
queue-review process and verify restricted operator access. A server-only
`moderation_hold` blocks publication and public lookup; request fields cannot set
or clear it. Normal members cannot review other people's reports or lift holds.

An operator can review pending reports in the private account database using their
operator role (not browser/public database access):

```sql
SELECT r.id, c.handle, r.category, r.reason, r.public_snapshot, r.created_at
FROM exp_member_community_report AS r
JOIN exp_member_community AS c ON c.user_id = r.target_id
ORDER BY r.created_at;
```

After reviewing a real report, a deliberate operator removal can both hold and
unpublish a profile. Replace the example handle only after review; no such action
was performed against hosted data during implementation:

```sql
UPDATE exp_member_community
SET moderation_hold = true, published_at = NULL, published_revision = NULL,
    published_name = NULL, published_bio = NULL, published_link = NULL,
    publication_version = NULL
WHERE handle = 'the-reviewed-handle';
```

Clearing that hold later leaves this removed publication empty; the member must
explicitly publish again. Record moderation decisions privately outside the repo.
This SQL/operator process is not a claim of a shipped moderation dashboard.

Reports retain a private evidence copy after unpublish. Deleting either the
reporting or reported account deletes the corresponding live reports. No scheduled
report expiry exists yet. Decide/implement the moderation retention period,
operator review frequency, support/privacy contact, log/backup access and restored-
backup erasure before enabling public profiles. The UI discloses these deletion/
copy boundaries; a live-store cascade is not a complete hosting retention policy.

## Storage, enablement and operational gates

- Apply `migrations/007_community_profiles.sql` once to the **account** database,
  after 003, with the migration role; existing 005/006 remain unchanged. Tables
  are private with PUBLIC privileges revoked. Grant the account runtime role
  required DML access on the three new tables, and verify grants separately.
- `ACCOUNT_COMMUNITY_ENABLED` defaults false. Draft preparation and unpublishing
  remain available with the flag off; public lookups return 404 and publishing/
  reporting are paused. No new schema is read merely by ordinary account sign-in.
  A previously saved publication remains private while the flag is off and can
  reappear when reopened unless the member explicitly unpublishes it.
- Per-member transactions serialize profile/report writes. Thirty draft changes,
  new publications and new reports per one-hour window; no-change saves/retries
  do not use new slots. The community write quota never blocks unpublish. Existing
  database-backed general IP abuse limits still apply.
- Before public enablement: hosted schema/grants/transport, public edge abuse
  limits, actual owner publish/view/unpublish and moderation-hold/report lifecycle,
  retention/privacy copy, keyboard and human VoiceOver review. Confirm the new
  endpoint and page headers on Vercel. No hosted flag, schema or deployment changed.
- Native editor, free exports, email purposes, Pro entitlements and optional usage
  collection are unchanged. News/preferences and private staff/author tickets stay
  separate next slices.

## Evidence

The initial new account behavior check failed with missing action 400 before
implementation (`/tmp/exp-community-gap.log`). Account suite now has 55 actual
PostgreSQL cases, including 10 community cases: exact public projection, private
draft/snapshot separation, stale preview/consent, unique/reserved handles, session/
field/link safety, paused operation/quota withdrawal, private report retries and
new-version evidence, holds, deletion cascades and storage failure. Full launch
suite has 107 service checks plus existing native Swift lifecycle/wire checks.

Final receipt: `output/a11y/2026-10-18T00-23-50-317Z/report.md` — **133 checks
passed, zero failed/blocked, 88 incomplete contrast scans** still needing review.
Full regression: `/tmp/exp-community-all-tests-confirmed.log`. Mobile editor/public
profile and dark desktop editor screenshots inspected without clipping. The
four Chromium/WebKit dark-desktop/light-mobile journeys exercise explicit save/
preview/consent/publication, cookie-free public reads, literal rendering, a second
verified reporter, unpublish→not-found, larger text and focus. Initial runs retained:
`output/a11y/2026-10-18T00-20-44-410Z/` (old beta helper's fixed 35-Tab ceiling) and
`output/a11y/2026-10-18T00-22-18-776Z/` (actual post-publication focus timing race).
The helper now bounds a whole page traversal without forcing focus; the UI moves
focus in React's layout-commit phase after result headings exist. These failures
are retained, not counted as passes. Human VoiceOver/Safari and hosted community
proof remain open even after automated checks pass.

W3C sources rechecked before form/name/status/disclosure changes:
[labels](https://www.w3.org/WAI/tutorials/forms/labels/),
[groups](https://www.w3.org/WAI/tutorials/forms/grouping/),
[status](https://www.w3.org/TR/wai-aria-1.2/#status),
[native details](https://www.w3.org/TR/html-aria/#el-details).

## Production enablement — October 21, 2026

Owner explicitly approved enabling public profiles and reviewing reports through
its private database queue. Set production `ACCOUNT_COMMUNITY_ENABLED=true` and
redeploy source `2c7089e0fc2fe72badc5797beea035e59b39d1c6` as
`dpl_HExmLVVyirKm6uHskoEXyD3UubtW`; READY, aliased to `expdesign.app`.
This supersedes the earlier paused-rollout status, not the historical evidence.

Read-only production preflight found zero saved publications, one private draft
and zero unresolved reports. Fresh owner Brave reload removes the paused notice,
loads the saved private preview and enables the unchecked publication choice.
Checking it enables Publish; unchecking disables Publish again. Leave it unchecked;
no Publish action was performed. Public lookup for `tapps` remains 404, with
`no-store`, `no-referrer` and `noindex` headers. Proof and sanitized receipt:
`output/a11y/community-launch-20261021/`.

The owner is the moderation operator using the existing private database console;
there is still no moderation dashboard or report email notification. Actual hosted
publish/view/unpublish and cross-account report/hold lifecycle evidence remain
open, as do the previously documented retention, backup and human accessibility
checks. Enabling the feature does not claim those checks have passed. No private
draft, testimonial or report was published as part of this operation.
