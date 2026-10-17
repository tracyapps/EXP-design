import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import { createInterestStore, hashToken } from '../server/interest/store.js';
import { createInterestHandlers } from '../server/interest/handlers.js';

const connectionString = process.env.EXP_INTEREST_TEST_DATABASE_URL;
// The integration runner creates this throwaway socket-only cluster. Refuse to
// truncate any ordinary database, including a developer's existing localhost DB.
const safe = connectionString && new URL(connectionString).searchParams.get('host')?.startsWith('/tmp/exp-interest-test.');
if (!safe) throw new Error('Run bash scripts/verify_pro_interest.sh to create an isolated database.');
const integration = test;
let pool, store, handlers, mails;
const env = { PRO_INTEREST_ENABLED: 'true', EXP_INTEREST_DATABASE_URL: 'local-test',
  RESEND_API_KEY: 'test-only', SIGNUP_FROM_EMAIL: 'EXP <hello@example.test>',
  INTEREST_PUBLIC_ORIGIN: 'https://example.test', NODE_ENV: 'test' };
const validRequest = () => ({ email: ' Person@Example.test ', model: 'either', consent: true,
  consentVersion: 'pro-interest-v1', source: 'pro page', website: '' });
async function call(name, body, method = 'POST', origin = 'https://example.test', service = handlers) {
  const headers = {}; let output;
  const response = { statusCode: 200, setHeader: (key, value) => { headers[key] = value; },
    end: value => { output = JSON.parse(value); } };
  await service[name]({ method, body, headers: { origin } }, response);
  return { status: response.statusCode, body: output, headers };
}
async function record() { return (await pool.query('SELECT * FROM exp_pro_interest')).rows[0]; }
const tokenFrom = link => new URL(link).hash.slice(1);
before(async () => {
  if (!safe) return;
  pool = new pg.Pool({ connectionString, max: 8 });
  await pool.query(await readFile(new URL('../migrations/001_pro_interest.sql', import.meta.url), 'utf8'));
  store = createInterestStore(pool);
});
after(async () => { if (pool) await pool.end(); });
beforeEach(async () => {
  if (!safe) return;
  await pool.query('TRUNCATE exp_pro_interest');
  mails = [];
  handlers = createInterestHandlers({ env, storeFactory: () => store,
    mailer: async (config, email, links) => { mails.push({ email, ...links }); } });
});

integration('request persists a pending record before mail; stores only token hashes', async () => {
  handlers = createInterestHandlers({ env, storeFactory: () => store, mailer: async (config, email, links) => {
    const saved = await record();
    assert.equal(saved.confirmed_at, null);
    assert.equal(saved.email, 'person@example.test');
    mails.push({ email, ...links });
  } });
  const result = await call('request', validRequest());
  assert.equal(result.status, 202);
  assert.equal(result.body.state, 'pending');
  const saved = await record();
  assert.equal(saved.token_hash, hashToken(tokenFrom(mails[0].confirm)));
  assert.equal(saved.withdrawal_hash, hashToken(tokenFrom(mails[0].withdraw)));
  assert.equal(saved.purpose, 'pro_interest');
  assert.equal(saved.consent_version, 'pro-interest-v1');
  assert.equal(saved.offer_version, 'pro-discovery-v1');
  assert.equal(new URL(mails[0].confirm).search, '');
  assert.ok(!JSON.stringify(saved).includes(tokenFrom(mails[0].confirm)));
});
integration('concurrent requests deduplicate atomically and only one mail is generated', async () => {
  const results = await Promise.all(Array.from({ length: 8 }, () => call('request', validRequest())));
  assert.ok(results.every(result => result.status === 202));
  assert.equal(mails.length, 1);
  assert.equal((await pool.query('SELECT count(*)::int AS count FROM exp_pro_interest')).rows[0].count, 1);
});
integration('exactly one concurrent confirmation consumes the token', async () => {
  await call('request', validRequest());
  const token = tokenFrom(mails[0].confirm);
  const results = await Promise.all(Array.from({ length: 8 }, () => call('confirm', { token })));
  assert.equal(results.filter(result => result.status === 200).length, 1);
  assert.equal(results.filter(result => result.status === 400).length, 7);
  const saved = await record();
  assert.ok(saved.confirmed_at);
  assert.equal(saved.token_hash, null);
});
integration('GET and a mail scanner visit cannot confirm or withdraw', async () => {
  await call('request', validRequest());
  assert.equal((await call('confirm', { token: tokenFrom(mails[0].confirm) }, 'GET')).status, 405);
  assert.equal((await call('withdraw', { token: tokenFrom(mails[0].withdraw) }, 'GET')).status, 405);
  assert.equal((await record()).confirmed_at, null);
  assert.equal((await record()).withdrawn_at, null);
});
integration('expired and tampered tokens never confirm', async () => {
  await call('request', validRequest());
  assert.equal((await call('confirm', { token: 'A'.repeat(43) })).status, 400);
  await pool.query("UPDATE exp_pro_interest SET expires_at = now() - interval '1 second'");
  assert.equal((await call('confirm', { token: tokenFrom(mails[0].confirm) })).status, 400);
  assert.equal((await record()).confirmed_at, null);
});
integration('withdrawal cancels pending confirmation and is repeatable', async () => {
  await call('request', validRequest());
  const token = tokenFrom(mails[0].withdraw);
  assert.equal((await call('withdraw', { token })).status, 200);
  assert.equal((await call('withdraw', { token })).status, 200);
  assert.equal((await call('confirm', { token: tokenFrom(mails[0].confirm) })).status, 400);
  assert.ok((await record()).withdrawn_at);
});
integration('a used confirmation cannot re-enroll after withdrawal', async () => {
  await call('request', validRequest());
  const token = tokenFrom(mails[0].confirm);
  await call('confirm', { token });
  await call('withdraw', { token: tokenFrom(mails[0].withdraw) });
  assert.equal((await call('confirm', { token })).status, 400);
  assert.equal((await pool.query('SELECT count(*)::int AS count FROM exp_pro_interest WHERE confirmed_at IS NOT NULL AND withdrawn_at IS NULL')).rows[0].count, 0);
});
integration('repeat confirmed signup preserves consent/model and sends no additional mail', async () => {
  await call('request', validRequest());
  await call('confirm', { token: tokenFrom(mails[0].confirm) });
  const original = await record();
  assert.equal((await call('request', { ...validRequest(), model: 'subscription' })).status, 202);
  const saved = await record();
  assert.equal(mails.length, 1);
  assert.equal(saved.model_preference, original.model_preference);
  assert.deepEqual(saved.requested_at, original.requested_at);
});
integration('after withdrawal, rejoining requires a fresh email token', async () => {
  await call('request', validRequest());
  const oldToken = tokenFrom(mails[0].confirm);
  await call('confirm', { token: oldToken });
  await call('withdraw', { token: tokenFrom(mails[0].withdraw) });
  await pool.query("UPDATE exp_pro_interest SET retry_after = now() - interval '1 second'");
  await call('request', { ...validRequest(), model: 'one_time' });
  assert.equal(mails.length, 2);
  assert.equal((await record()).confirmed_at, null);
  assert.equal((await call('confirm', { token: oldToken })).status, 400);
  assert.equal((await call('confirm', { token: tokenFrom(mails[1].confirm) })).status, 200);
  assert.equal((await record()).model_preference, 'one_time');
});
integration('mail failure invalidates that token and permits a fresh immediate retry', async () => {
  const failed = createInterestHandlers({ env, storeFactory: () => store, mailer: async () => { throw new Error('private provider error'); } });
  assert.equal((await call('request', validRequest(), 'POST', 'https://example.test', failed)).status, 502);
  assert.equal((await record()).token_hash, null);
  assert.equal((await call('request', validRequest())).status, 202);
  assert.equal(mails.length, 1);
});
integration('missing consent, unknown source/model, malformed body and cross-origin requests fail before mail', async () => {
  for (const body of [null, [], '{', { ...validRequest(), consent: false }, { ...validRequest(), model: 'lifetime_free' },
    { ...validRequest(), source: 'private filename' }, { ...validRequest(), consentVersion: 'old' }]) {
    assert.equal((await call('request', body)).status, 400);
  }
  assert.equal((await call('request', validRequest(), 'POST', 'https://attacker.test')).status, 403);
  assert.equal(mails.length, 0);
  assert.equal(await record(), undefined);
});
integration('feature is off by default and database failure cannot announce pending success', async () => {
  const off = createInterestHandlers({ env: { ...env, PRO_INTEREST_ENABLED: undefined }, storeFactory: () => { throw new Error('must not access database'); } });
  assert.equal((await call('request', validRequest(), 'POST', 'https://example.test', off)).status, 503);
  const broken = createInterestHandlers({ env, storeFactory: () => ({ request: async () => { throw new Error('private database error'); } }) });
  assert.equal((await call('request', validRequest(), 'POST', 'https://example.test', broken)).status, 502);
  assert.equal(mails.length, 0);
});
integration('real mail boundary uses only Resend email transport, with fragment links and no contact enrollment', async () => {
  const originalFetch = globalThis.fetch; const calls = [];
  globalThis.fetch = async (url, options) => {
    assert.ok((await record()).token_hash, 'persistence precedes mail');
    calls.push({ url, body: JSON.parse(options.body) });
    return new Response(JSON.stringify({ id: 'mail-test-id' }), { status: 200 });
  };
  try {
    const service = createInterestHandlers({ env, storeFactory: () => store });
    assert.equal((await call('request', validRequest(), 'POST', 'https://example.test', service)).status, 202);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://api.resend.com/emails');
    assert.match(calls[0].body.text, /confirm-interest#[A-Za-z0-9_-]{43}/);
    assert.match(calls[0].body.text, /withdraw-interest#[A-Za-z0-9_-]{43}/);
  } finally { globalThis.fetch = originalFetch; }
});
integration('withdrawal remains available when enrollment is paused and email credentials are absent', async () => {
  await call('request', validRequest());
  await call('confirm', { token: tokenFrom(mails[0].confirm) });
  const paused = createInterestHandlers({ env: { ...env, PRO_INTEREST_ENABLED: undefined,
    RESEND_API_KEY: undefined, SIGNUP_FROM_EMAIL: undefined }, storeFactory: () => store });
  assert.equal((await call('withdraw', { token: tokenFrom(mails[0].withdraw) }, 'POST', 'https://example.test', paused)).status, 200);
  assert.ok((await record()).withdrawn_at);
});
integration('production origin configuration rejects insecure or non-origin URLs', async () => {
  for (const origin of ['http://example.test', 'http://localhost:5190', 'https://example.test/pro', 'https://user:pass@example.test', 'https://example.test?redirect=elsewhere']) {
    const service = createInterestHandlers({ env: { ...env, NODE_ENV: 'production', INTEREST_PUBLIC_ORIGIN: origin },
      storeFactory: () => { throw new Error('must not access database'); } });
    assert.equal((await call('request', validRequest(), 'POST', origin, service)).status, 503);
  }
});
integration('operational errors do not log database credentials, email or capability tokens', async () => {
  const originalWarn = console.warn; const logs = [];
  console.warn = (...args) => logs.push(args);
  try {
    const privateValue = 'person@example.test private-database-password private-token';
    const service = createInterestHandlers({ env, storeFactory: () => ({ request: async () => { throw new Error(privateValue); } }) });
    const result = await call('request', validRequest(), 'POST', 'https://example.test', service);
    assert.equal(result.status, 502);
    const output = JSON.stringify({ result, logs });
    for (const value of privateValue.split(' ')) assert.ok(!output.includes(value));
  } finally { console.warn = originalWarn; }
});
