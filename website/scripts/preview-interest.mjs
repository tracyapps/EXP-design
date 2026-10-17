// Local acceptance harness: actual handlers + isolated PostgreSQL + captured mail.
// It cannot send email. Start with scripts/preview_pro_interest.sh.
import http from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { createServer } from 'vite';
import { createInterestStore } from '../../server/interest/store.js';
import { createInterestHandlers } from '../../server/interest/handlers.js';

const databaseURL = process.env.EXP_INTEREST_TEST_DATABASE_URL;
const socket = databaseURL && new URL(databaseURL).searchParams.get('host');
if (!socket?.startsWith('/tmp/exp-interest-test.') || process.env.NODE_ENV === 'production') {
  throw new Error('Use the isolated local preview runner');
}
const port = Number(process.env.EXP_INTEREST_PREVIEW_PORT || 5190);
const origin = `http://127.0.0.1:${port}`;
const pool = new pg.Pool({ connectionString: databaseURL });
await pool.query(await readFile(new URL('../../migrations/001_pro_interest.sql', import.meta.url), 'utf8'));
const mailbox = [];
const handlers = createInterestHandlers({ env: { PRO_INTEREST_ENABLED: 'true', EXP_INTEREST_DATABASE_URL: databaseURL,
  RESEND_API_KEY: 'local-capture-only', SIGNUP_FROM_EMAIL: 'EXP <local@example.test>', INTEREST_PUBLIC_ORIGIN: origin,
  NODE_ENV: 'development' }, storeFactory: () => createInterestStore(pool), mailer: async (config, email, links) => {
    mailbox.push({ email, ...links });
    await writeFile(`${socket}/mailbox.json`, JSON.stringify(mailbox), { mode: 0o600 });
  } });
const routes = { '/api/pro-interest': handlers.request, '/api/confirm-interest': handlers.confirm,
  '/api/withdraw-interest': handlers.withdraw };
const vite = await createServer({ root: fileURLToPath(new URL('..', import.meta.url)),
  server: { middlewareMode: true }, appType: 'spa' });
const server = http.createServer(async (request, response) => {
  const handler = routes[request.url];
  if (!handler) return vite.middlewares(request, response);
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 2048) { response.writeHead(413).end(); return; }
  }
  request.body = body;
  await handler(request, response);
});
server.listen(port, '127.0.0.1', () => console.log(`Local preview: ${origin}/pro\nCaptured test mail: ${socket}/mailbox.json`));
async function close() { server.close(); await vite.close(); await pool.end(); process.exit(0); }
process.on('SIGTERM', close); process.on('SIGINT', close);
