import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
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
  service = createAccountService({ pool, origin, secret, sendOTP: async mail => {
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
