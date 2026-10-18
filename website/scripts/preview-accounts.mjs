// Actual account service and PostgreSQL, with mail captured only to private temp.
import http from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { createServer } from 'vite';
import { createAccountService } from '../../server/accounts/service.js';
import { createAccountNodeHandler } from '../../server/accounts/runtime.js';
import { createInterestStore } from '../../server/interest/store.js';
import { createInterestHandlers } from '../../server/interest/handlers.js';
import { createPublicProfileHandler } from '../../server/accounts/community.js';
const databaseURL = process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
const socket = databaseURL && new URL(databaseURL).searchParams.get('host');
if (!socket?.startsWith('/tmp/exp-account-test.') || process.env.NODE_ENV === 'production') throw new Error('Use scripts/verify_accounts.sh --preview');
const pool = new pg.Pool({ connectionString: databaseURL });
for (const file of ['001_pro_interest.sql', '002_pro_interest_erasure.sql', '003_free_accounts.sql', '005_member_beta.sql', '006_account_pro_link.sql', '007_community_profiles.sql']) {
  await pool.query(await readFile(new URL(`../../migrations/${file}`, import.meta.url), 'utf8'));
}
const origin = 'http://127.0.0.1:5191', mailbox = [];
async function capture(mail) {
  mailbox.push(mail);
  await writeFile(`${socket}/mailbox.json`, JSON.stringify(mailbox), { mode: 0o600 });
}
const store = createInterestStore(pool);
const service = createAccountService({ pool, origin, secret: randomBytes(32).toString('hex'), betaEnabled: true,
  interestStore: store, proLinkEnabled: true, communityEnabled:true, sendOTP: mail => capture({ kind: 'account', ...mail }) });
const account = createAccountNodeHandler({ handle: service.handle, origin, env: {} });
const people = createAccountNodeHandler({handle:createPublicProfileHandler({pool,enabled:true}),origin,env:{}});
const interest = createInterestHandlers({ env: { PRO_INTEREST_ENABLED: 'true', EXP_INTEREST_DATABASE_URL: databaseURL,
  INTEREST_PUBLIC_ORIGIN: origin, RESEND_API_KEY: 'capture-only', SIGNUP_FROM_EMAIL: 'fixture@example.test' },
  storeFactory: () => store, mailer: (config, email, links) => capture({ kind: 'interest', email, ...links }),
  erasureMailer: (config, email, links) => capture({ kind: 'erasure', email, ...links }) });
const routes = { '/api/pro-interest': interest.request, '/api/confirm-interest': interest.confirm,
  '/api/withdraw-interest': interest.withdraw, '/api/request-interest-erasure': interest.requestErasure, '/api/delete-interest': interest.erase };
const vite = await createServer({ root: fileURLToPath(new URL('..', import.meta.url)), server: { middlewareMode: true }, appType: 'spa' });
const server = http.createServer(async (request, response) => {
  if (request.url.split('?')[0] === '/api/account') return account(request, response);
  if (request.url.split('?')[0] === '/api/people') return people(request, response);
  if (routes[request.url.split('?')[0]]) {
    let body = ''; for await (const chunk of request) { body += chunk; if (body.length > 4096) { response.writeHead(413).end(); return; } }
    request.body = body; return routes[request.url.split('?')[0]](request, response);
  }
  if (request.url.startsWith('/api/')) { response.writeHead(404).end(); return; }
  vite.middlewares(request, response);
});
server.listen(5191, '127.0.0.1', () => console.log(`Local account preview: ${origin}/account\nCaptured test mail: ${socket}/mailbox.json`));
async function close() { server.close(); await vite.close(); await pool.end(); process.exit(0); }
process.on('SIGTERM', close); process.on('SIGINT', close);
