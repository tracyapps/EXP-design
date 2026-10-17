import test, { beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/signup.js';

const keys = ['RESEND_API_KEY', 'SIGNUP_STORE_CONTACTS', 'RESEND_SIGNUP_SEGMENT_ID', 'RESEND_RELEASE_TOPIC_ID', 'SIGNUP_TO_EMAIL', 'SIGNUP_FROM_EMAIL'];
const originalEnv = Object.fromEntries(keys.map(key => [key, process.env[key]]));
const originalFetch = globalThis.fetch;
let calls;
beforeEach(() => {
  Object.assign(process.env, { RESEND_API_KEY: 'test-key', SIGNUP_STORE_CONTACTS: 'true', RESEND_SIGNUP_SEGMENT_ID: 'release-segment', RESEND_RELEASE_TOPIC_ID: 'release-topic', SIGNUP_TO_EMAIL: 'owner@example.test', SIGNUP_FROM_EMAIL: 'EXP <hello@example.test>' });
  calls = [];
});
afterEach(() => {
  globalThis.fetch = originalFetch;
  for (const key of keys) originalEnv[key] === undefined ? delete process.env[key] : process.env[key] = originalEnv[key];
});
function provider(steps) {
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url, ...options, body: options.body ? JSON.parse(options.body) : undefined });
    const next = steps.shift();
    assert.ok(next, 'unexpected provider request');
    if (next instanceof Error) throw next;
    return new Response(JSON.stringify(next.body ?? {}), { status: next.status ?? 200 });
  };
}
async function signup(body, method = 'POST') {
  if (arguments.length === 0) body = { email: 'person@example.test', source: 'download page' };
  let result;
  const headers = {};
  const response = { statusCode: 200, setHeader: (key, value) => { headers[key] = value; }, end: text => { result = JSON.parse(text); } };
  await handler({ method, body }, response);
  return { status: response.statusCode, body: result, headers };
}
const contact = (extra = {}) => ({ id: 'contact-1', email: 'person@example.test', unsubscribed: false, ...extra });
const memberships = () => [
  { body: { data: [{ id: 'release-topic', subscription: 'opt_in' }], has_more: false } },
  { body: { data: [{ id: 'release-segment' }], has_more: false } },
];

test('storage disabled never announces list success or sends email', async () => {
  process.env.SIGNUP_STORE_CONTACTS = 'false';
  provider([{ body: { id: 'email-1' } }]);
  assert.equal((await signup()).status, 503);
  assert.equal(calls.length, 0);
});
test('provider storage failure never becomes signup success', async () => {
  provider([{ status: 404 }, { status: 500 }]);
  assert.equal((await signup()).status, 502);
  assert.ok(calls.every(call => !call.url.endsWith('/emails')));
});
test('malformed and non-object payloads return 400 without provider calls', async () => {
  provider([]);
  for (const body of [null, undefined, [], 7, 'null', '{', { email: ['person@example.test'] }]) {
    assert.equal((await signup(body)).status, 400);
  }
  assert.equal(calls.length, 0);
});
test('new contact is stored before optional notification; purpose is release-only', async () => {
  provider([{ status: 404 }, { status: 201, body: { id: 'contact-1', object: 'contact' } }, { status: 500 }]);
  const result = await signup({ email: ' Person@Example.test ', source: 'download page' });
  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(calls[1].url, 'https://api.resend.com/contacts');
  assert.equal(calls[2].url, 'https://api.resend.com/emails');
  assert.equal(calls[1].body.email, 'person@example.test');
  assert.equal(calls[1].body.unsubscribed, undefined, 'do not force a global resubscribe');
  assert.equal(calls[1].body.properties.signup_purpose, 'release_updates');
  assert.equal(calls[1].body.properties.consent_version, 'release-updates-v1');
  assert.ok(!Number.isNaN(Date.parse(calls[1].body.properties.signed_up_at)));
  assert.deepEqual(calls[1].body.topics, [{ id: 'release-topic', subscription: 'opt_in' }]);
});
test('active duplicate verifies topic and segment, without writes or notification', async () => {
  provider([{ body: contact() }, ...memberships()]);
  assert.equal((await signup()).status, 200);
  assert.equal(calls.length, 3);
  assert.ok(calls.every(call => call.method === 'GET'));
});
test('global and topic opt-outs are preserved, never silently resubscribed', async () => {
  provider([{ body: contact({ unsubscribed: true }) }]);
  assert.equal((await signup()).status, 502);
  assert.ok(calls.every(call => call.method === 'GET'));
  calls = [];
  provider([{ body: contact() }, { body: { data: [{ id: 'release-topic', subscription: 'opt_out' }] } }]);
  assert.equal((await signup()).status, 502);
  assert.ok(calls.every(call => call.method === 'GET'));
});
test('conflict is not success unless the existing release subscription is verified', async () => {
  provider([{ status: 404 }, { status: 409 }, { status: 404 }]);
  assert.equal((await signup()).status, 502);
  calls = [];
  provider([{ status: 404 }, { status: 409 }, { body: contact() }, ...memberships()]);
  assert.equal((await signup()).status, 200);
  assert.ok(!calls.some(call => call.url.endsWith('/emails')));
});
test('network errors and malformed provider success fail closed', async () => {
  for (const steps of [[new Error('private provider details')], [{ status: 404 }, { status: 201, body: {} }], [{ body: {} }]]) {
    provider(steps);
    assert.equal((await signup()).status, 502);
  }
});
test('source and purpose are allowlisted; honeypot causes no provider work', async () => {
  provider([]);
  assert.equal((await signup({ email: 'person@example.test', source: 'private document name' })).status, 400);
  assert.equal((await signup({ email: 'person@example.test', purpose: 'marketing' })).status, 400);
  assert.equal((await signup({ email: 'person@example.test', website: 'bot' })).body.ok, true);
  assert.equal(calls.length, 0);
});

test('required routing configuration is checked before touching a contact', async () => {
  provider([]);
  for (const key of ['RESEND_API_KEY', 'RESEND_SIGNUP_SEGMENT_ID', 'RESEND_RELEASE_TOPIC_ID']) {
    const value = process.env[key];
    delete process.env[key];
    assert.equal((await signup()).status, 503);
    process.env[key] = value;
  }
  assert.equal(calls.length, 0);
});
test('unknown membership, missing segment and upstream throttling never claim success', async () => {
  const cases = [
    [{ status: 429 }],
    [{ body: contact() }, { body: { data: [], has_more: true } }],
    [{ body: contact() }, memberships()[0], { body: { data: [], has_more: false } }],
    [{ body: contact() }, { status: 429 }],
  ];
  for (const steps of cases) {
    calls = [];
    provider(steps);
    assert.equal((await signup()).status, 502);
    assert.ok(calls.every(call => call.method === 'GET'));
  }
});
test('transport failure after a durable save still succeeds, and retry performs no writes', async () => {
  provider([{ status: 404 }, { status: 201, body: { id: 'contact-1', object: 'contact' } }, new Error('notification network failure')]);
  assert.equal((await signup()).body.ok, true);
  calls = [];
  provider([{ body: contact() }, ...memberships()]);
  assert.equal((await signup()).body.ok, true);
  assert.ok(calls.every(call => call.method === 'GET'));
});
test('no owner mail configuration is needed for durable signup', async () => {
  delete process.env.SIGNUP_TO_EMAIL;
  delete process.env.SIGNUP_FROM_EMAIL;
  provider([{ status: 404 }, { status: 201, body: { id: 'contact-1', object: 'contact' } }]);
  assert.equal((await signup()).status, 200);
  assert.equal(calls.length, 2);
});
test('failure logs and public errors contain no address, secret or upstream detail', async () => {
  const originalWarn = console.warn;
  const logs = [];
  console.warn = (...args) => logs.push(args);
  try {
    provider([new Error('person@example.test test-key upstream private payload')]);
    const result = await signup();
    process.env.SIGNUP_STORE_CONTACTS = 'false';
    await signup();
    const output = JSON.stringify({ logs, result });
    for (const privateValue of ['person@example.test', 'test-key', 'upstream private payload']) {
      assert.ok(!output.includes(privateValue));
    }
    assert.equal(result.headers['cache-control'], 'no-store');
  } finally { console.warn = originalWarn; }
});
test('unsupported methods advertise POST and never call the provider', async () => {
  provider([]);
  const result = await signup({}, 'GET');
  assert.equal(result.status, 405);
  assert.equal(result.headers.allow, 'POST');
  assert.equal(calls.length, 0);
});
