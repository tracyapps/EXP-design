// Actual account service and PostgreSQL, with mail captured only to private temp.
import http from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { createServer } from 'vite';
import { createAccountService } from '../../server/accounts/service.js';
import { createAccountNodeHandler } from '../../server/accounts/runtime.js';
const databaseURL = process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
const socket = databaseURL && new URL(databaseURL).searchParams.get('host');
if (!socket?.startsWith('/tmp/exp-account-test.') || process.env.NODE_ENV === 'production') throw new Error('Use scripts/verify_accounts.sh --preview');
const pool = new pg.Pool({ connectionString: databaseURL });
await pool.query(await readFile(new URL('../../migrations/003_free_accounts.sql', import.meta.url), 'utf8'));
await pool.query(await readFile(new URL('../../migrations/005_member_beta.sql', import.meta.url), 'utf8'));
const origin = 'http://127.0.0.1:5191', mailbox = [];
const service = createAccountService({ pool, origin, secret: randomBytes(32).toString('hex'), betaEnabled: true, async sendOTP(mail) {
  mailbox.push(mail);
  await writeFile(`${socket}/mailbox.json`, JSON.stringify(mailbox), { mode: 0o600 });
} });
const account = createAccountNodeHandler({ handle: service.handle, origin, env: {} });
const vite = await createServer({ root: fileURLToPath(new URL('..', import.meta.url)), server: { middlewareMode: true }, appType: 'spa' });
const server = http.createServer(async (request, response) => {
  if (request.url.split('?')[0] === '/api/account') return account(request, response);
  if (request.url.startsWith('/api/')) { response.writeHead(404).end(); return; }
  vite.middlewares(request, response);
});
server.listen(5191, '127.0.0.1', () => console.log(`Local account preview: ${origin}/account\nCaptured test mail: ${socket}/mailbox.json`));
async function close() { server.close(); await vite.close(); await pool.end(); process.exit(0); }
process.on('SIGTERM', close); process.on('SIGINT', close);
