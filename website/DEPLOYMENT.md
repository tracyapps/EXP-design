# EXP [design] website deployment

The website is deployed from the same private GitHub repo as the macOS app.
Keep the Vercel project rooted at the repository root so the build can read
`docs/ROADMAP.md` and `docs/BACKLOG.md`.

## Vercel project settings

Import the existing GitHub repo and use these settings:

```text
Root Directory: ./
Framework Preset: Other
Install Command: cd website && npm ci
Build Command: cd website && npm run build
Output Directory: website/dist
```

The root `vercel.json` stores those same commands so Vercel should pick them up
automatically after the repo is connected.

Do not set the Vercel root directory to `website/` unless you also enable
Vercel's setting to include source files outside the root directory. The sync
script intentionally reads files from `../docs`.

## Auto-sync content

Every local or Vercel build runs:

```bash
cd website
npm run sync
```

That script reads:

```text
docs/ROADMAP.md
docs/BACKLOG.md
```

and generates:

```text
website/src/generated/siteContent.json
```

The generated JSON is ignored by Git because it includes a build timestamp and
should be recreated from the Markdown source each time.

## Daily workflow

1. Update `docs/ROADMAP.md` at the end of a work session.
2. Update `docs/BACKLOG.md` when bugs/features change.
3. Commit and push.
4. Vercel rebuilds the site from the repo root.

No manual website copy changes are needed for roadmap/backlog updates.

## Local commands

```bash
cd website
npm install
npm run dev
npm run build
```

`npm run dev` and `npm run build` both run the sync first.

## Email signup

The tester signup form posts to `api/signup.js`, a small Vercel Function that
sends a notification email through Resend. The same endpoint can also add the
address to Resend Contacts for release broadcasts.

Set these Vercel environment variables:

```text
RESEND_API_KEY=<your Resend API key>
SIGNUP_TO_EMAIL=<where signup notifications should go>
SIGNUP_FROM_EMAIL=EXP [design] <hello@expdesign.app>
```

Optional contact-list storage:

```text
SIGNUP_STORE_CONTACTS=true
RESEND_SIGNUP_SEGMENT_ID=<optional Resend segment id>
RESEND_RELEASE_TOPIC_ID=<optional Resend topic id>
```

If `SIGNUP_STORE_CONTACTS=true`, use a Resend API key that can create contacts.
Without that flag, the form still emails each signup to `SIGNUP_TO_EMAIL`.

For the cleanest production setup, verify `expdesign.app` in Resend first, then
use an address on that domain for `SIGNUP_FROM_EMAIL`. For a quick test, Resend's
`onboarding@resend.dev` sender can be used while the domain is being verified.

## Release notifications

The simplest release-notification workflow is:

1. Publish a GitHub Release with build notes and assets.
2. Use the Resend contact segment/topic created by the signup form.
3. Send a Resend Broadcast manually with the release notes and direct GitHub
   release links.

A later automation can turn this into a protected Vercel Function or GitHub
Action that reads the newest GitHub Release, drafts a broadcast, and waits for a
manual send/approve step.

## Public content filtering

Website builds auto-sync progress from `docs/ROADMAP.md`, but small website-only
maintenance entries should not clutter the public roadmap or release-notification
drafts. Add one of these markers to the progress-log title when an entry should
stay internal:

```text
[site]
[website]
[internal]
```

Example:

```text
- **2026-07-05 — Session 186 [site]:** Updated the public website...
```
