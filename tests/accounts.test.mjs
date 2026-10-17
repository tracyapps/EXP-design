import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import http from 'node:http';
import pg from 'pg';
import { getMigrations } from 'better-auth/db/migration';
import { createAccountService, accountConsentVersion } from '../server/accounts/service.js';
import { accountConfiguration, createAccountNodeHandler } from '../server/accounts/runtime.js';

const db = process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
if (!db || !new URL(db).searchParams.get('host')?.startsWith('/tmp/exp-account-test.')) throw new Error('Disposable local PostgreSQL required');
const pool = new pg.Pool({ connectionString: db });
const origin = 'https://accounts.example.test';
const mailbox = [];
const secret = randomBytes(32).toString('hex');
let failMail = false, ip = 0;
let service;
before(async () => {
  await pool.query(await readFile(new URL('../migrations/003_free_accounts.sql', import.meta.url), 'utf8'));
  await pool.query(await readFile(new URL('../migrations/005_member_beta.sql', import.meta.url), 'utf8'));
  service = createAccountService({ pool, origin, secret, betaEnabled: true, sendOTP: async mail => {
  if (failMail) throw new Error('Mail transport failure with private data');
  mailbox.push(mail);
} });
});
after(async () => { await pool.end(); });

async function call(body, cookie = '', options = {}) {
  const response = await service.handle(new Request(`${origin}${options.path || '/api/account'}`, {
    method: body ? 'POST' : 'GET', headers: { origin, 'content-type': 'application/json',
      'x-exp-client-ip': `192.0.2.${++ip % 250 + 1}`, cookie, ...options.headers }, body: body ? JSON.stringify(body) : undefined
  }));
  return { status: response.status, body: await response.json(), headers: response.headers,
    cookie: response.headers.getSetCookie().map(c => c.split(';')[0]).join('; ') };
}
async function code(email) {
  const response = await call({ action: 'send-code', email });
  assert.equal(response.status, 200, JSON.stringify(response.body));
  return mailbox.findLast(mail => mail.email === email).otp;
}
async function register(email) {
  const otp = await code(email);
  const result = await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Test Designer',
    accountConsent: true, consentVersion: accountConsentVersion });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.ok(result.cookie);
  return result.cookie;
}
async function resetCooldown(email) {
  // Only the disposable test DB; exercise subsequent flows without wall-clock sleeps.
  await pool.query("UPDATE exp_member_mail_limit SET sent_at = now() - interval '61 seconds'");
}

test('reviewed migration matches the pinned auth schema', async () => {
  const migration = await getMigrations(service.options);
  assert.deepEqual(migration.toBeCreated, []);
  assert.deepEqual(migration.toBeAdded, []);
  assert.deepEqual(migration.toBeAddedIndexes, []);
});
test('anonymous session has no profile; private routes require authentication', async () => {
  const result = await call();
  assert.deepEqual(result.body, { ok: true, registrationOpen: true, user: null });
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.equal((await call({ action: 'save-profile', name: 'Nobody', bio: '', link: '' })).status, 401);
});
test('beta participation starts off and invitation permission requires its own explicit choice', async () => {
  const cookie = await register('beta-choice@example.test');
  const initial = await call({ action: 'beta' }, cookie);
  assert.equal(initial.status, 200);
  assert.deepEqual(initial.body.participation, { participating: false, inviteEmails: false, updatedAt: null });
  assert.deepEqual(initial.body.feedback, []);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
  const joined = await call({ action: 'beta' }, cookie);
  assert.equal(joined.body.participation.participating, true);
  assert.equal(joined.body.participation.inviteEmails, false);
  assert.ok(joined.body.participation.updatedAt);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie)).status, 400);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'old' }, cookie)).status, 400);
});
test('private feedback is durable, retry-safe and isolated by verified account ownership', async () => {
  const alice = await register('beta-alice@example.test'), bob = await register('beta-bob@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Keyboard flow', message: '<script>literal text</script>' };
  const replies = await Promise.all(Array.from({ length: 4 }, () => call(body, alice)));
  assert.ok(replies.every(reply => reply.status === 200));
  const saved = await call({ action: 'beta' }, alice);
  assert.equal(saved.body.feedback.length, 1);
  assert.equal(saved.body.feedback[0].message, body.message);
  assert.equal(saved.body.feedback[0].status, 'received');
  assert.deepEqual((await call({ action: 'beta' }, bob)).body.feedback, []);
  assert.equal((await call({ ...body, message: 'Changed retry' }, alice)).status, 409);
  assert.equal((await call(body, bob)).status, 409);
  assert.equal((await call({ action: 'delete-beta-feedback', id: body.id }, bob)).status, 404);
  assert.equal((await call({ action: 'delete-beta-feedback', id: body.id }, alice)).status, 200);
  assert.deepEqual((await call({ action: 'beta' }, alice)).body.feedback, []);
});
test('beta actions reject anonymous, revoked, unverified and forged-ownership requests', async () => {
  assert.equal((await call({ action: 'beta' })).status, 401);
  const cookie = await register('beta-auth@example.test');
  for (const extra of [{ userId: randomUUID() }, { status: 'resolved' }, { email: 'someone@example.test' }, { releaseEmails: true }]) {
    assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1', ...extra }, cookie)).status, 400);
  }
  await pool.query('UPDATE exp_member_user SET "emailVerified"=false WHERE email=$1', ['beta-auth@example.test']);
  assert.equal((await call({ action: 'beta' }, cookie)).status, 401);
  await pool.query('UPDATE exp_member_user SET "emailVerified"=true WHERE email=$1', ['beta-auth@example.test']);
  await call({ action: 'sign-out-all' }, cookie);
  assert.equal((await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'No', message: 'Revoked' }, cookie)).status, 401);
});
test('feedback content is bounded and cannot create arbitrary status or attachment records', async () => {
  const cookie = await register('beta-validation@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Valid', message: 'Valid' };
  for (const extra of [{ subject: ' ' }, { message: '' }, { subject: 'x'.repeat(121) }, { message: 'x'.repeat(1501) }, { id: "' OR true" }, { status: 'reviewed' }, { attachment: 'file.design' }]) {
    assert.equal((await call({ ...body, ...extra }, cookie)).status, 400);
  }
  assert.deepEqual((await call({ action: 'beta' }, cookie)).body.feedback, []);
});
test('beta choices survive service restart; withdrawal preserves feedback and other account preferences', async () => {
  const cookie = await register('beta-withdraw@example.test');
  await call({ action: 'save-preferences', largeText: true }, cookie);
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Keep', message: 'My feedback' }, cookie);
  const restarted = createAccountService({ pool, origin, secret, sendOTP: async () => {} });
  const response = await restarted.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', cookie, 'x-exp-client-ip': '192.0.2.100' }, body: JSON.stringify({ action: 'beta' }) }));
  const before = await response.json();
  assert.equal(before.participation.inviteEmails, true);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: false, permissionVersion: 'old' }, cookie)).status, 200);
  const after = (await call({ action: 'beta' }, cookie)).body;
  assert.equal(after.participation.participating, false); assert.equal(after.participation.inviteEmails, false);
  assert.equal(after.feedback.length, 1);
  assert.equal((await call(undefined, cookie)).body.user.largeText, true);
  assert.equal(mailbox.filter(mail => mail.email === 'beta-withdraw@example.test').length, 1, 'only the requested sign-in code was sent');
});
test('write quota is shared and cannot prevent withdrawal or deleting feedback', async () => {
  const cookie = await register('beta-quota@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  const id = randomUUID();
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id, subject: 'Saved', message: 'Before quota' }, cookie);
  await pool.query('UPDATE exp_member_beta_limit SET count=30 WHERE user_id=$1', [userId]);
  assert.equal((await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Blocked', message: 'Quota' }, cookie)).status, 429);
  assert.equal((await call({ action: 'submit-beta-feedback', id, subject: 'Saved', message: 'Before quota' }, cookie)).status, 200, 'committed retry still succeeds');
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
  assert.equal((await call({ action: 'save-beta', participating: false, inviteEmails: false }, cookie)).status, 200);
  assert.equal((await call({ action: 'delete-beta-feedback', id }, cookie)).status, 200);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 429);
  await pool.query("UPDATE exp_member_beta_limit SET window_start=now()-interval '61 minutes' WHERE user_id=$1", [userId]);
  assert.equal((await call({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' }, cookie)).status, 200);
});
test('feedback cap stays at fifty under concurrent submissions', async () => {
  const cookie = await register('beta-cap@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  await pool.query("INSERT INTO exp_member_beta_feedback(id,user_id,subject,message) SELECT gen_random_uuid(),$1,'Existing','Note' FROM generate_series(1,49)", [userId]);
  const replies = await Promise.all(Array.from({ length: 4 }, () => call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Last', message: 'Note' }, cookie)));
  assert.equal(replies.filter(reply => reply.status === 200).length, 1);
  assert.equal(replies.filter(reply => reply.status === 409).length, 3);
  assert.equal((await call({ action: 'beta' }, cookie)).body.feedback.length, 50);
});
test('pausing beta admits no new choices or feedback while preserving withdrawal, reads and deletion', async () => {
  const cookie = await register('beta-pause@example.test');
  const id = randomUUID();
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id, subject: 'Keep', message: 'Saved' }, cookie);
  const paused = createAccountService({ pool, origin, secret, betaEnabled: false, sendOTP: async () => {} });
  const post = async body => paused.handle(new Request(`${origin}/api/account`, { method: 'POST', headers: {
    origin, 'content-type': 'application/json', cookie, 'x-exp-client-ip': '192.0.2.110' }, body: JSON.stringify(body) }));
  assert.equal((await (await post({ action: 'beta' })).json()).betaOpen, false);
  assert.equal((await post({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'New', message: 'No' })).status, 503);
  assert.equal((await post({ action: 'save-beta', participating: true, inviteEmails: false, permissionVersion: 'beta-participation-v1' })).status, 200);
  assert.equal((await post({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' })).status, 503);
  assert.equal((await post({ action: 'save-beta', participating: false, inviteEmails: false })).status, 200);
  assert.equal((await post({ action: 'delete-beta-feedback', id })).status, 200);
});
test('storage failure cannot report feedback success; same request can retry after recovery', async () => {
  const cookie = await register('beta-failure@example.test');
  const body = { action: 'submit-beta-feedback', id: randomUUID(), subject: 'Retry', message: 'Private database error' };
  await pool.query(`CREATE FUNCTION exp_beta_test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private database detail'; END $$;
    CREATE TRIGGER exp_beta_test_failure BEFORE INSERT ON exp_member_beta_feedback FOR EACH ROW EXECUTE FUNCTION exp_beta_test_failure()`);
  try {
    const reply = await call(body, cookie);
    assert.equal(reply.status, 503);
    assert.doesNotMatch(JSON.stringify(reply.body), /private database detail|beta-failure/);
    assert.deepEqual((await call({ action: 'beta' }, cookie)).body.feedback, []);
  } finally { await pool.query('DROP TRIGGER exp_beta_test_failure ON exp_member_beta_feedback; DROP FUNCTION exp_beta_test_failure()'); }
  assert.equal((await call(body, cookie)).status, 200);
  assert.equal((await call({ action: 'beta' }, cookie)).body.feedback.length, 1);
});
test('account deletion cascades live beta choices, feedback and quota rows', async () => {
  const cookie = await register('beta-delete@example.test');
  const userId = (await call(undefined, cookie)).body.user.id;
  await call({ action: 'save-beta', participating: true, inviteEmails: true, permissionVersion: 'beta-participation-v1' }, cookie);
  await call({ action: 'submit-beta-feedback', id: randomUUID(), subject: 'Remove', message: 'Private' }, cookie);
  assert.equal((await call({ action: 'delete-account', confirmation: 'DELETE' }, cookie)).status, 200);
  for (const table of ['exp_member_beta', 'exp_member_beta_feedback', 'exp_member_beta_limit']) {
    assert.equal((await pool.query(`SELECT count(*) FROM ${table} WHERE user_id=$1`, [userId])).rows[0].count, '0');
  }
  assert.equal((await call({ action: 'beta' }, cookie)).status, 401);
});
test('requesting a code does not create an account; code is not stored in cleartext', async () => {
  const otp = await code('pending@example.test');
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email = $1', ['pending@example.test'])).rowCount, 0);
  const values = (await pool.query('SELECT value FROM exp_member_verification')).rows;
  assert.ok(values.length > 0);
  assert.ok(values.every(row => !row.value.includes(otp)));
});
test('ordinary sign-in cannot silently create an account even with a valid code', async () => {
  const email = 'no-registration@example.test', otp = await code(email);
  assert.equal((await call({ action: 'verify-code', email, otp, intent: 'sign-in' })).status, 400);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 0);
});
test('registration requires explicit current consent and a display name', async () => {
  for (const extra of [{ accountConsent: false }, { consentVersion: 'old' }, { name: '' }]) {
    assert.equal((await call({ action: 'verify-code', email: 'bad@example.test', otp: '123456', intent: 'register',
      name: 'Test', accountConsent: true, consentVersion: accountConsentVersion, ...extra })).status, 400);
  }
});
test('verified account is private, has a stable random ID, no bearer token in JSON and secure cookie', async () => {
  const cookie = await register('first@example.test');
  const result = await call(undefined, cookie);
  assert.equal(result.body.user.profileVisibility, 'private');
  assert.equal(result.body.user.largeText, false);
  assert.match(result.body.user.id, /^[a-f0-9-]{36}$/);
  assert.equal(result.body.token, undefined);
  assert.equal(result.body.session, undefined);
  const stored = (await pool.query('SELECT * FROM exp_member_user WHERE email=$1', ['first@example.test'])).rows[0];
  assert.equal(stored.emailVerified, true);
  assert.equal(stored.accountConsentVersion, accountConsentVersion);
  assert.ok(stored.accountAcceptedAt);
  const email = 'cookie@example.test', otp = await code(email);
  const signed = await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Cookie', accountConsent: true, consentVersion: accountConsentVersion });
  const setCookie = signed.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/i); assert.match(setCookie, /Secure/i); assert.match(setCookie, /SameSite=Lax/i);
  assert.deepEqual(signed.body, { ok: true });
});
test('valid code is consumed once under simultaneous verification', async () => {
  const email = 'race@example.test', otp = await code(email);
  const replies = await Promise.all(Array.from({ length: 8 }, () => call({ action: 'verify-code', email, otp,
    intent: 'register', name: 'Race', accountConsent: true, consentVersion: accountConsentVersion })));
  assert.equal(replies.filter(r => r.status === 200).length, 1);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 1);
});
test('expired code cannot create a session', async () => {
  const email = 'expired@example.test', otp = await code(email);
  await pool.query('UPDATE exp_member_verification SET "expiresAt" = now() - interval \'1 second\' WHERE identifier LIKE $1', [`%${email}%`]);
  assert.notEqual((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Expired', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('five failed attempts exhaust a challenge even across client IPs', async () => {
  const email = 'attempts@example.test', otp = await code(email);
  const wrong = otp === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) assert.notEqual((await call({ action: 'verify-code', email, otp: wrong, intent: 'sign-in' })).status, 200);
  assert.notEqual((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Attempts', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('per-address cooldown is shared across instances and does not rotate the delivered code', async () => {
  const email = 'cooldown@example.test', otp = await code(email);
  const second = createAccountService({ pool, origin, secret, sendOTP: async mail => mailbox.push(mail) });
  const responses = await Promise.all(Array.from({ length: 6 }, () => second.handle(new Request(`${origin}/api/account`, {
    method: 'POST', headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '198.51.100.9' },
    body: JSON.stringify({ action: 'send-code', email })
  }))));
  assert.ok(responses.every(r => r.status === 429));
  assert.equal(mailbox.filter(mail => mail.email === email).length, 1);
  assert.equal((await call({ action: 'verify-code', email, otp, intent: 'register', name: 'Cooldown', accountConsent: true, consentVersion: accountConsentVersion })).status, 200);
});
test('mail failure returns an error without leaking transport detail', async () => {
  failMail = true;
  try {
    const response = await call({ action: 'send-code', email: 'failure@example.test' });
    assert.ok(response.status >= 500);
    assert.doesNotMatch(JSON.stringify(response.body), /private data|failure@example/);
  } finally { failMail = false; }
});
test('profile and preferences persist and are isolated between two users', async () => {
  const alice = await register('alice@example.test'), bob = await register('bob@example.test');
  assert.equal((await call({ action: 'save-profile', name: 'Alice', bio: '<script>private</script>', link: 'https://example.test/alice' }, alice)).status, 200);
  assert.equal((await call({ action: 'save-preferences', largeText: true }, alice)).status, 200);
  assert.equal((await call(undefined, alice)).body.user.bio, '<script>private</script>');
  assert.equal((await call(undefined, alice)).body.user.largeText, true);
  assert.equal((await call(undefined, bob)).body.user.bio, '');
  assert.equal((await call(undefined, bob)).body.user.largeText, false);
  const bobId = (await call(undefined, bob)).body.user.id;
  assert.equal((await call({ action: 'save-profile', name: 'Attack', bio: '', link: '', userId: bobId }, alice)).status, 400);
  assert.equal((await call({ action: 'save-preferences', largeText: true, profileVisibility: 'public' }, bob)).status, 400);
  assert.equal((await call(undefined, bob)).body.user.name, 'Test Designer');
});
test('unsafe links, oversized names, email changes and marketing flags are rejected', async () => {
  for (const body of [
    { action: 'save-profile', name: 'X', bio: '', link: 'javascript:alert(1)' },
    { action: 'save-profile', name: 'X', bio: '', link: 'https://user:secret@example.test' },
    { action: 'save-profile', name: 'x'.repeat(81), bio: '', link: '' },
    { action: 'save-preferences', largeText: 'true' },
    { action: 'save-preferences', largeText: true, releaseEmails: true },
    { action: 'save-profile', name: 'X', bio: '', link: '', email: 'other@example.test' }
  ]) assert.equal((await call(body)).status, 400);
});
test('logout revokes the server session; replaying the old cookie stays signed out', async () => {
  const cookie = await register('logout@example.test');
  assert.equal((await call({ action: 'sign-out' }, cookie)).status, 200);
  assert.equal((await call(undefined, cookie)).body.user, null);
});
test('sign out everywhere revokes sessions created by another service instance', async () => {
  const email = 'everywhere@example.test', first = await register(email);
  await resetCooldown(email);
  const otp = await code(email);
  const second = await call({ action: 'verify-code', email, otp, intent: 'sign-in' });
  assert.equal(second.status, 200);
  assert.equal((await call({ action: 'sign-out-all' }, first)).status, 200);
  assert.equal((await call(undefined, first)).body.user, null);
  assert.equal((await call(undefined, second.cookie)).body.user, null);
});
test('deletion requires confirmation and recent authentication, then removes profile and all sessions', async () => {
  const email = 'delete@example.test', cookie = await register(email);
  assert.equal((await call({ action: 'delete-account', confirmation: 'yes' }, cookie)).status, 400);
  await pool.query('UPDATE exp_member_session SET "createdAt"=now() - interval \'6 minutes\' WHERE "userId"=(SELECT id FROM exp_member_user WHERE email=$1)', [email]);
  const stale = await call({ action: 'delete-account', confirmation: 'DELETE' }, cookie);
  assert.equal(stale.status, 400);
  assert.match(stale.body.error, /fresh code/);
  await resetCooldown(email);
  const fresh = await call({ action: 'verify-code', email, otp: await code(email), intent: 'sign-in' });
  assert.equal((await call({ action: 'delete-account', confirmation: 'DELETE' }, fresh.cookie)).status, 200);
  assert.equal((await pool.query('SELECT * FROM exp_member_user WHERE email=$1', [email])).rowCount, 0);
  assert.equal((await call(undefined, cookie)).body.user, null);
  assert.equal((await call(undefined, fresh.cookie)).body.user, null);
});
test('wrong/missing origin, foreign fetch, raw library routes and identity fields fail closed', async () => {
  assert.equal((await call({ action: 'send-code', email: 'csrf@example.test' }, '', { headers: { origin: 'https://evil.example' } })).status, 403);
  assert.equal((await call(undefined, '', { headers: { 'sec-fetch-site': 'cross-site' } })).status, 403);
  assert.equal((await call(undefined, '', { path: '/api/auth/get-session' })).status, 404);
  assert.equal((await call({ action: 'admin', role: 'staff' })).status, 400);
  const missing = await service.handle(new Request(`${origin}/api/account`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }));
  assert.equal(missing.status, 403);
});
test('database-backed IP limiter is enforced across auth instances', async () => {
  const headers = { 'x-exp-client-ip': '203.0.113.10' };
  for (let i = 0; i < 5; i++) assert.equal((await call({ action: 'send-code', email: `ip-limit-${i}@example.test` }, '', { headers })).status, 200);
  assert.equal((await call({ action: 'send-code', email: 'ip-limit-final@example.test' }, '', { headers })).status, 429);
  assert.ok((await pool.query('SELECT * FROM exp_member_rate_limit')).rowCount > 0);
});
test('hosted configuration requires exact HTTPS origin, separate DB and strong secret', () => {
  const env = { NODE_ENV: 'production', ACCOUNT_PUBLIC_ORIGIN: origin, EXP_ACCOUNT_DATABASE_URL: 'postgres://local?sslmode=verify-full', BETTER_AUTH_SECRET: secret };
  assert.ok(accountConfiguration(env));
  assert.equal(accountConfiguration({ ...env, ACCOUNT_PUBLIC_ORIGIN: origin + '/' }), null);
  assert.equal(accountConfiguration({ ...env, ACCOUNT_PUBLIC_ORIGIN: 'http://localhost' }), null);
  assert.equal(accountConfiguration({ ...env, BETTER_AUTH_SECRET: 'short' }), null);
  assert.equal(accountConfiguration({ ...env, EXP_ACCOUNT_DATABASE_URL: '' }), null);
  assert.equal(accountConfiguration({ ...env, EXP_ACCOUNT_DATABASE_URL: 'postgres://local?sslmode=require' }), null);
});
test('Node adapter works over HTTP and overwrites spoofed IP/host headers', async () => {
  const adapter = createAccountNodeHandler({ handle: service.handle, origin, env: {} });
  const server = http.createServer(adapter);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/account`, { headers: { origin, 'x-exp-client-ip': 'evil' } });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, registrationOpen: true, user: null });
  } finally { await new Promise(resolve => server.close(resolve)); }
});
test('paused registration still permits existing-member access, logout and deletion', async () => {
  const email = 'pause@example.test', cookie = await register(email);
  const paused = createAccountService({ pool, origin, secret, registrationEnabled: false, sendOTP: async mail => mailbox.push(mail) });
  const request = (body, session = cookie) => paused.handle(new Request(`${origin}/api/account`, {
    method: body ? 'POST' : 'GET', headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '198.51.100.44', cookie: session },
    body: body ? JSON.stringify(body) : undefined
  }));
  const current = await (await request()).json();
  assert.equal(current.registrationOpen, false);
  assert.equal(current.user.email, email);
  const freshEmail = 'paused-new@example.test', otp = await code(freshEmail);
  assert.equal((await request({ action: 'verify-code', email: freshEmail, otp, intent: 'register', name: 'No', accountConsent: true, consentVersion: accountConsentVersion }, '')).status, 400);
  assert.equal((await request({ action: 'delete-account', confirmation: 'DELETE' })).status, 200);
  assert.equal((await call(undefined, cookie)).body.user, null);
});
test('oversized and malformed request bodies are rejected before auth actions', async () => {
  assert.equal((await call({ action: 'save-profile', name: 'X', bio: 'x'.repeat(5000), link: '' })).status, 413);
  const result = await service.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': '192.0.2.70' }, body: '{' }));
  assert.equal(result.status, 400);
});
test('per-address hourly cap blocks the sixth message and rolls over after one hour', async () => {
  const email = 'hour-cap@example.test';
  for (let i = 0; i < 5; i++) { await resetCooldown(email); await code(email); }
  await resetCooldown(email);
  assert.equal((await call({ action: 'send-code', email })).status, 429);
  await pool.query("UPDATE exp_member_mail_limit SET window_start=now()-interval '61 minutes', sent_at=now()-interval '61 seconds'");
  assert.equal((await call({ action: 'send-code', email })).status, 200);
});
test('mail failure state cannot bleed into another concurrent request', async () => {
  const isolated = createAccountService({ pool, origin, secret, sendOTP: async ({ email }) => {
    if (email.startsWith('fail-')) throw new Error('captured failure');
  } });
  const send = email => isolated.handle(new Request(`${origin}/api/account`, { method: 'POST',
    headers: { origin, 'content-type': 'application/json', 'x-exp-client-ip': email.startsWith('fail-') ? '192.0.2.85' : '192.0.2.86' },
    body: JSON.stringify({ action: 'send-code', email }) }));
  const [failed, successful] = await Promise.all([send('fail-concurrent@example.test'), send('success-concurrent@example.test')]);
  assert.equal(failed.status, 503);
  assert.equal(successful.status, 200);
});
test('Node adapter supports pre-parsed Vercel-style JSON bodies and trusts only the platform IP', async () => {
  const adapter = createAccountNodeHandler({ handle: service.handle, origin, env: { VERCEL: '1' } });
  const server = http.createServer(async (request, response) => {
    let raw = ''; for await (const chunk of request) raw += chunk;
    request.body = JSON.parse(raw);
    await adapter(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const reply = await fetch(`http://127.0.0.1:${server.address().port}/api/account`, {
      method: 'POST', headers: { origin, 'content-type': 'application/json',
        'x-exp-client-ip': 'spoofed', 'x-vercel-forwarded-for': '198.51.100.55' },
      body: JSON.stringify({ action: 'send-code', email: 'parsed@example.test' })
    });
    assert.equal(reply.status, 200);
    assert.ok(mailbox.some(mail => mail.email === 'parsed@example.test'));
    assert.ok((await pool.query('SELECT key FROM exp_member_rate_limit WHERE key LIKE $1', ['%198.51.100.55%'])).rowCount > 0);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
