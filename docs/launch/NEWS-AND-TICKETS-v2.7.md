# News, email choice and private support — FEAT-069

October 17, 2026. Continues the owner-selected free member hub. Local source only;
no deployment, hosted migration, staff grant or real email is authorized here.

## Delivered behavior

- `/news` is public, account-free and makes no account API request. The first
  curated post describes shipped v2.6, from `RELEASE-NOTES-v2.6.md` and its release
  receipt. Internal roadmap/progress notes are never its feed. Add future posts
  deliberately in `website/src/NewsPage.jsx`; do not announce unreleased work as
  shipped. No editor/CMS, analytics or email sender was added to this page.
- Preferences has a separate, initially unchecked development-news email choice.
  Explicit opt-in records `development-news-v1`, verified account UUID and server
  timestamp. Saving or withdrawing never touches release, beta or Pro permission,
  sends email or publishes profile information. The UI states delivery is not
  active. One current choice receipt is stored, not a historical campaign ledger.
  Before any sender is built, design campaign evidence, suppression, withdrawal,
  delivery and retention; query current permission immediately before each send.
- `/account/tickets` opens private text tickets, lists the member's threads,
  shows all replies and open/closed history, replies, closes/reopens and explicitly
  deletes an authored thread. Replies are visible to the author and authorized
  support staff; there are no hidden staff notes or attachments. No design file,
  device information, diagnostic log or private profile is automatically attached.
- `/account/support` is an operator-granted staff inbox using the same verified
  account session. It lists ticket subjects/status/time, opens threads, replies
  as “EXP support” and changes status. It cannot delete another member's ticket.
  No staff email, profile, account UUID or grant information is returned to authors.
  Check the website for replies: no ticket email notifier or response-time promise
  exists. Beta feedback remains separate and is not silently converted to tickets.

## Authorization and data

`migrations/008_news_and_tickets.sql` is additive, in the **account database**,
after 003. Existing deployed accounts are preserved. Do not rerun earlier
migrations as a reset. No runtime auto-migration exists.

| Private table | Stored fields / lifecycle |
| --- | --- |
| `exp_member_news` | Current boolean permission, wording version, timestamp, account UUID; account deletion cascades |
| `exp_member_support_grant` | Explicit operator grant to account UUID, timestamp and private operator reference; account deletion cascades; runtime SELECT only |
| `exp_member_ticket` | Random UUID, owning account UUID, subject 120 characters, status, revision, creation/update time; author deletion or account deletion cascades |
| `exp_member_ticket_event` | Random retry receipt, thread UUID, actor UUID, author/support marker, message up to 1,500 characters or status event, sequence/time; thread deletion cascades |
| `exp_member_ticket_limit` | Account UUID, one-hour window and count; account deletion cascades |
| `exp_member_support_audit` | Thread UUID, staff actor UUID, read/reply/status action and time; thread deletion cascades |

All tables revoke PUBLIC access. Staff thread reads and changes must commit a
private audit row or fail. Queue metadata reads do not create an audit row. Audit
records are not exposed in either account UI. Deleting a staff account clears its
actor UUID from replies/audits in other authors' threads; the support label and
answer remain. Deleting the ticket author removes the whole thread, every reply
and its audits. Explicit ticket deletion requires typing DELETE. Provider logs,
mail, exports/copies and backups have separate retention. No automatic ticket or
audit expiry job exists yet; choose and operate that policy before hosted rollout.

Every action derives identity from the library-verified session and reads current
staff grants from the database. Client-supplied user IDs, roles, authors, timestamps,
attachment fields and arbitrary statuses are rejected. Another ordinary member
gets the same 404 for a foreign thread/cursor as a missing one. Staff access is
revoked by deleting the grant; there is no cached session role. An in-flight action
that already read its grant may complete after revocation; subsequent actions fail.
Account rows and then ticket rows serialize writes and caps. There is no
role-grant endpoint, email-address allowlist, first-user promotion or public signup
shortcut to staff access.

## Limits, retries and outage behavior

- At most 50 saved tickets per author, enforced under the account-row lock.
  Lists return 25 at a time, with an authorized cursor. The live queue is not a
  frozen snapshot; concurrent updates may move items between pages.
- At most 200 history entries per thread, plus a final close if needed. Closed
  threads cannot take replies; capped threads cannot reopen. Deletion remains
  available. Messages are plain text, not rendered HTML or automatic links.
- Thirty new tickets/replies/reopens per actor/hour in shared PostgreSQL, plus
  existing IP/account service limits. Successful same-content retries, reads,
  closing and deleting do not consume that write quota. General IP protection
  still applies. Database indexes cover owner/queue, event sequence and foreign
  keys, including account deletion and audit lookup.
- Browser-generated random receipts bind retries to unchanged content. A lost
  response after commit can retry without a second ticket/reply. Changed content
  with the old receipt conflicts. Revisions refuse concurrent stale changes and
  preserve the browser's draft for refresh/retry. Confirmed mutations clear stale
  thread claims before refresh; failed refresh shows a reload path. Draft text
  stays in the current page only, not browser storage; leaving/reloading loses it.
- Input JSON is capped at 12 KiB for ticket creation/replies to support bounded
  multilingual text; all other account actions retain the 4 KiB limit. Field limits
  still apply. SQL parameters and generic errors prevent user content becoming SQL
  or database internals leaking on failure. Failed transactions roll back quotas,
  thread changes, history and audit together.
- `ACCOUNT_TICKETS_ENABLED=false` pauses new tickets/replies/reopening. Existing
  threads, staff review, author deletion and closing remain available when the
  schema/service is configured. `ACCOUNT_NEWS_ENABLED=false` pauses new news-email
  permission but permits reading/withdrawing a saved choice. Neither flag stops
  the public static news page. Both default false.

## Operator setup before private hosted testing

1. Review/apply only unapplied migration 008 with an administration/migration
   role. The prior community slice separately needs 007. Keep new flags false.
2. Use a restricted runtime login, **not the Neon owner/migration login**.
   Grant schema USAGE, then the permissions below. These role names are placeholders
   for the product roles in the Neon setup guide; commands are not run automatically.

   ```sql
   GRANT SELECT, INSERT, UPDATE, DELETE ON exp_member_news,
     exp_member_ticket, exp_member_ticket_event, exp_member_ticket_limit
     TO exp_account_runtime;
   GRANT SELECT, INSERT ON exp_member_support_audit TO exp_account_runtime;
   REVOKE ALL ON exp_member_support_grant FROM exp_account_runtime;
   GRANT SELECT ON exp_member_support_grant TO exp_account_runtime;
   ```

   Confirm the runtime login does not own these tables or inherit an administrative
   role. Merely revoking a direct grant cannot constrain an owner or inherited
   privileges. Runtime cannot insert/update/delete staff grants. Keep current auth
   table grants and the separate interest database boundary intact.
3. Owner signs into their own verified EXP account. An authorized database operator
   privately verifies its UUID and inserts a grant with an operator reference:

   ```sql
   -- Replace the quoted UUID placeholder privately in the SQL editor.
   -- First verify the intended account's UUID and verified email as operator.
   INSERT INTO exp_member_support_grant(user_id, operator_reference)
     SELECT id, 'Owner support access approved' FROM exp_member_user
     WHERE id = 'REPLACE_WITH_VERIFIED_ACCOUNT_UUID'::uuid AND "emailVerified" = true
     RETURNING user_id;
   -- Revoke when needed; no app redeploy/session refresh required.
   DELETE FROM exp_member_support_grant
     WHERE user_id = 'REPLACE_WITH_VERIFIED_ACCOUNT_UUID'::uuid;
   ```

   There is no shipped staff-grant web UI. Test a second ordinary member against
   private ticket reads/writes and the support inbox, then verify revocation.
4. Approve privacy/retention/restore-erasure, staff access and inbox coverage,
   edge abuse limits and actual server-role isolation before authorizing new
   hosted writes. Enable only the reviewed flags in the correct environment,
   redeploy only with separate authorization, then test author → staff answer →
   author read/close/delete using approved test accounts. No public rollout or
   sending is inferred from local test success.
5. Verify actual Safari/VoiceOver, zoom/large text, keyboard/focus and provider
   failures. Automated results do not close the outstanding contrast/human AT gate.

## Evidence

Initial feature-gap checks returned missing-action 400 before implementation:
`/tmp/exp-news-tickets-gap.log`. The account suite now passes 71 real PostgreSQL
checks, including news permission isolation/pause/deletion/failure; author/staff
boundaries; current grants/revocation; retries/concurrency/revisions; caps and
pagination; quota-independent closure/deletion; staff anonymization and cascades;
Unicode/field limits; atomic rollback; and runtime denial of grant insertion plus a full service journey through a non-owner
role with read-only grant access. The latter caught an inappropriate FOR SHARE
lock (requires UPDATE privileges); grants now use a plain current-row read. Gap
receipt: `/tmp/exp-news-tickets-role-gap.log`.
Full combined regression and final browser receipts are recorded in ROADMAP and
the release checklist. Browser scenarios use actual HTTP, database sessions and
captured synthetic codes; staff grants are made only by the test fixture's private
Node-side database operator, never a browser-accessible endpoint.

Final `npm test`: **123 service checks** (15 signup, 23 Pro, 71 account, 14 usage)
plus existing native lifecycle and actual HTTP→DB checks, exit 0:
`/tmp/exp-news-tickets-regression-final.log`. Final browser matrix/build:
`output/a11y/2026-10-18T00-38-23-663Z/report.md` — **173 passed, zero failed/blocked,
116 incomplete contrast scans / 57 distinct review items**. First browser run also
passed at `output/a11y/2026-10-18T00-35-40-768Z/`; final run follows the grant-query
fix. Screenshots of news, mobile author and dark staff views inspected without
horizontal overflow. Incomplete contrast review and human Safari/VoiceOver,
hosted two-account/operator lifecycle, provider roles/TLS, logs/backup/retention
and response coverage remain unverified. None is inferred from these local results.

The PostgreSQL privilege behavior was also checked against the primary
[SELECT documentation](https://www.postgresql.org/docs/current/sql-select.html):
locking SELECT variants require UPDATE privilege. The app keeps the grant query
read-only rather than broadening the runtime's grant-table privileges.

Standards checked before semantic/naming/focus changes: W3C
[native labels](https://www.w3.org/WAI/tutorials/forms/labels/),
[fieldset/legend](https://www.w3.org/WAI/tutorials/forms/grouping/),
[status](https://www.w3.org/TR/wai-aria-1.2/#status),
[ARIA in HTML](https://www.w3.org/TR/html-aria/),
[keyboard interface](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/),
[WCAG 2.1 focus order](https://www.w3.org/TR/WCAG21/#focus-order).
