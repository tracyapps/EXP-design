import http from 'node:http';
import { spawn } from 'node:child_process';
import pg from 'pg';
import assert from 'node:assert/strict';
import { createUsageHandler, usageStore } from '../server/usage/collector.js';
const pool = new pg.Pool({ connectionString: process.env.EXP_USAGE_TEST_DATABASE_URL, max: 2 });
const store = usageStore(pool);
const handler = createUsageHandler({ env: { EXP_USAGE_ENABLED: 'true', EXP_USAGE_HOST_VERIFIED: 'true', EXP_USAGE_DATABASE_URL: 'test' }, storeFactory: () => store });
await pool.query('TRUNCATE exp_usage_events, exp_usage_limits');
let requests = 0, exfiltrations = 0;
const server = http.createServer(async (request, response) => {
  if (request.url === '/exfiltrate') { exfiltrations++; response.end(); return; }
  if (request.url === '/redirect') { response.writeHead(302, { location: '/exfiltrate' }); response.end(); return; }
  const chunks = []; let size = 0;
  for await (const chunk of request) { size += chunk.length; if (size > 16384) { response.writeHead(413); response.end(); return; } chunks.push(chunk); }
  requests++;
  assert.equal(request.headers.cookie, undefined); assert.equal(request.headers.authorization, undefined);
  assert.equal(request.headers['user-agent'], 'EXP-Usage/1');
  request.body = Buffer.concat(chunks).toString('utf8');
  await handler(request, response);
});
try {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const code = await new Promise((resolve, reject) => {
    const child = spawn(process.env.EXP_USAGE_CHECK_BINARY, [`${origin}/api/usage`, `${origin}/redirect`], { stdio: 'inherit' });
    child.on('error', reject); child.on('exit', resolve);
  });
  assert.equal(code, 0); assert.equal(requests, 1); assert.equal(exfiltrations, 0);
  const records = (await pool.query('SELECT event_name FROM exp_usage_events')).rows;
  assert.equal(records.length, 6); assert.ok(records.some(row => row.event_name === 'activation_completed'));
  console.log('PASS: one actual native request, six durable rows, no cookies/auth or redirect following');
} finally { server.close(); await pool.end(); }
