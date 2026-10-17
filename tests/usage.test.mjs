import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import { createUsageHandler, usageStore } from '../server/usage/collector.js';

const connectionString = process.env.EXP_USAGE_TEST_DATABASE_URL;
if (!connectionString || !new URL(connectionString).searchParams.get('host')?.startsWith('/tmp/exp-usage-test.')) throw new Error('Run bash scripts/verify_usage_metrics.sh');
let pool, store;
const env = { EXP_USAGE_ENABLED: 'true', EXP_USAGE_HOST_VERIFIED: 'true', EXP_USAGE_DATABASE_URL: 'test-only' };
const event = (name = 'work_started') => ({ id: randomUUID(), name, day: new Date().toISOString().slice(0, 10),
  appVersion: '2.7', osMajor: 26, ...(['work_started', 'work_edited', 'output_completed'].includes(name) ? { source: 'new' } : {}),
  ...(name === 'output_completed' ? { output: 'png' } : {}) });
const batch = () => ({ schemaVersion: 1, consentVersion: 'usage-v1', installID: randomUUID(), events: [event()] });
async function call(body, { service = createUsageHandler({ env, storeFactory: () => store }), method = 'POST', headers = {} } = {}) {
  const response = { statusCode: 0, headers: {}, setHeader(key, value) { this.headers[key] = value; }, end(body) { this.body = body; } };
  await service({ method, body, headers: { 'content-type': 'application/json', ...headers } }, response);
  return response;
}
async function rows() { return (await pool.query('SELECT * FROM exp_usage_events')).rows; }
before(async () => {
  pool = new pg.Pool({ connectionString, max: 8 });
  await pool.query(await readFile(new URL('../migrations/004_usage_metrics.sql', import.meta.url), 'utf8'));
  store = usageStore(pool);
});
after(async () => { await pool.end(); });
beforeEach(async () => { await pool.query('TRUNCATE exp_usage_events, exp_usage_limits'); });

test('collector is disabled unless hosting review and explicit switch are both configured', async () => {
  for (const config of [{}, { ...env, EXP_USAGE_ENABLED: 'false' }, { ...env, EXP_USAGE_HOST_VERIFIED: '' }]) {
    const service = createUsageHandler({ env: config, storeFactory: () => { throw new Error('must not touch storage'); } });
    assert.equal((await call(batch(), { service })).statusCode, 503);
  }
  assert.equal((await rows()).length, 0);
});
test('durable success returns 204 with no-store and no response identifiers', async () => {
  const payload = batch(), result = await call(payload);
  assert.equal(result.statusCode, 204); assert.equal(result.body, '');
  assert.equal(result.headers['cache-control'], 'no-store');
  const row = (await rows())[0];
  assert.equal(row.install_id, payload.installID);
  assert.equal(row.event_name, 'work_started');
  assert.equal(row.source, 'new');
});
test('concurrent retry of one batch records each event only once', async () => {
  const payload = batch(); payload.events.push(event('work_edited'), event('output_completed'), event('activation_completed'));
  const responses = await Promise.all(Array.from({ length: 8 }, () => call(payload)));
  assert.ok(responses.every(response => response.statusCode === 204));
  assert.equal((await rows()).length, 4);
});
test('install and active-day milestones deduplicate even with replacement event UUIDs', async () => {
  const payload = batch(); payload.events = [event('eligible_first_run'), event('activation_completed'), event('active_day')];
  await call(payload);
  payload.events = [event('eligible_first_run'), event('activation_completed'), event('active_day')];
  await call(payload); assert.equal((await rows()).length, 3);
});
test('rejects unknown top-level data instead of accepting personal metadata', async () => {
  for (const extra of [{ email: 'private@example.test' }, { document: { text: 'secret' } }, { path: '/private/name.design' }]) {
    assert.equal((await call({ ...batch(), ...extra })).statusCode, 400);
  }
  assert.equal((await rows()).length, 0);
});
test('rejects free-text event attributes and unexpected enum values', async () => {
  for (const change of [{ filename: 'secret.design' }, { source: 'private-file.svg' }, { name: 'clicked secret' }, { output: 'private/path.png' }, { appVersion: 'user@example.test' }, { osMajor: 'Mac serial' }]) {
    const payload = batch(); Object.assign(payload.events[0], change);
    assert.equal((await call(payload)).statusCode, 400);
  }
});
test('source/output dimensions are restricted to the matching event types', async () => {
  const payload = batch(); payload.events = [{ ...event('active_day'), source: 'new' }];
  assert.equal((await call(payload)).statusCode, 400);
  payload.events = [{ ...event(), output: 'png' }]; assert.equal((await call(payload)).statusCode, 400);
  payload.events = [{ ...event('output_completed'), output: null }]; assert.equal((await call(payload)).statusCode, 400);
});
test('rejects invalid schema, consent, UUID, dates and oversized batches', async () => {
  for (const change of [{ schemaVersion: 2 }, { consentVersion: 'yes' }, { installID: 'email@example.test' }, { events: [] }, { events: Array.from({ length: 33 }, () => event()) }]) {
    assert.equal((await call({ ...batch(), ...change })).statusCode, 400);
  }
  for (const day of ['2026-02-30', '2000-01-01', '2099-01-01', 'today']) {
    const payload = batch(); payload.events[0].day = day;
    assert.equal((await call(payload)).statusCode, 400);
  }
  assert.equal((await call('{broken')).statusCode, 400);
  assert.equal((await call(' '.repeat(17000))).statusCode, 400);
});
test('GET, browser origins and non-JSON content never create records', async () => {
  assert.equal((await call(batch(), { method: 'GET' })).statusCode, 405);
  assert.equal((await call(batch(), { headers: { origin: 'https://example.test' } })).statusCode, 403);
  assert.equal((await call(batch(), { headers: { 'content-type': 'text/plain' } })).statusCode, 415);
  assert.equal((await rows()).length, 0);
});
test('storage failure cannot acknowledge acceptance', async () => {
  const service = createUsageHandler({ env, storeFactory: () => ({ accept() { throw new Error('private connection details'); } }) });
  assert.equal((await call(batch(), { service })).statusCode, 503);
});
test('daily install budget bounds admission and retry traffic', async () => {
  const payload = batch(); payload.events = Array.from({ length: 32 }, () => event());
  for (let index = 0; index < 8; index++) assert.equal((await call(payload)).statusCode, 204);
  assert.equal((await call(payload)).statusCode, 429);
  assert.equal((await rows()).length, 32);
});
test('a transaction failure rolls back both batch and rate budget', async () => {
  const payload = batch(); payload.events.push({ ...event(), output: 'invalid' });
  await assert.rejects(store.accept(payload));
  assert.equal((await rows()).length, 0);
  assert.equal((await pool.query('SELECT * FROM exp_usage_limits')).rowCount, 0);
});
test('retention job deletes expired rows and preserves current data without live traffic', async () => {
  await call(batch());
  const old = batch(); await call(old);
  await pool.query("UPDATE exp_usage_events SET received_at = now() - interval '29 days 12 hours' WHERE install_id=$1", [old.installID]);
  await pool.query("UPDATE exp_usage_limits SET received_day = CURRENT_DATE - 31 WHERE install_id=$1", [old.installID]);
  await store.purge(); assert.equal((await rows()).length, 1);
  assert.equal((await pool.query('SELECT * FROM exp_usage_limits')).rowCount, 1);
});
test('stored schema contains no account, IP, email, document or arbitrary payload columns', async () => {
  const result = await pool.query("SELECT column_name FROM information_schema.columns WHERE table_name='exp_usage_events'");
  assert.deepEqual(result.rows.map(row => row.column_name).sort(), ['install_id','event_id','consent_version','event_name','event_day','app_version','os_major','source','output','received_at'].sort());
});
