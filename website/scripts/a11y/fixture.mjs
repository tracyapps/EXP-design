// Real local account/interest services, disposable PG and captured mail. No
// provider credentials, network sends or browser-accessible test-mail endpoint.
import http from 'node:http';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import pg from 'pg';
import { createAccountService } from '../../../server/accounts/service.js';
import { createAccountNodeHandler } from '../../../server/accounts/runtime.js';
import { createPublicProfileHandler } from '../../../server/accounts/community.js';
import { createInterestHandlers } from '../../../server/interest/handlers.js';
import { createInterestStore } from '../../../server/interest/store.js';

export async function startFixture() {
  const databaseURL = process.env.EXP_A11Y_DATABASE_URL;
  if (!databaseURL || !new URL(databaseURL).searchParams.get('host')?.startsWith('/tmp/exp-a11y-pg.') || process.env.NODE_ENV === 'production') throw Error('Disposable accessibility runner required');
  const pool = new pg.Pool({ connectionString: databaseURL });
  for (const name of ['001_pro_interest.sql', '002_pro_interest_erasure.sql', '003_free_accounts.sql', '005_member_beta.sql', '006_account_pro_link.sql', '007_community_profiles.sql']) {
    await pool.query(await readFile(new URL(`../../../migrations/${name}`, import.meta.url), 'utf8'));
  }
  const mail = [], errors = [], dist = path.resolve(fileURLToPath(new URL('../../dist/', import.meta.url)));
  let account, routes, people;
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://127.0.0.1');
      if (url.pathname === '/api/account') return await account(request, response);
      if (url.pathname === '/api/people') return await people(request, response);
      if (routes[url.pathname]) {
        let body = ''; for await (const chunk of request) { body += chunk; if (body.length > 4096) { response.writeHead(413).end(); return; } }
        request.body = body; return await routes[url.pathname](request, response);
      }
      if (url.pathname === '/api/signup') { // Mail-list provider boundary fixture only.
        response.writeHead(503, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: 'Release signup is unavailable in this local fixture.' })); return;
      }
      if (url.pathname.startsWith('/api/')) { response.writeHead(404).end(); return; }
      const requested = url.pathname === '/support' ? '/support.html' : url.pathname;
      const filename = path.resolve(dist, `.${requested}`);
      if (!filename.startsWith(dist + path.sep) && filename !== dist) { response.writeHead(404).end(); return; }
      const extension = path.extname(filename);
      const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
      const data = await readFile(extension ? filename : path.join(dist, 'index.html'));
      response.writeHead(200, { 'Content-Type': types[extension] || 'text/html', 'Cache-Control': 'no-store' }).end(data);
    } catch { errors.push('Local fixture request failed'); response.writeHead(500).end(); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  const service = createAccountService({ pool, origin, secret: randomBytes(32).toString('hex'), betaEnabled: true,
    interestStore: createInterestStore(pool), proLinkEnabled: true, communityEnabled:true, sendOTP: async item => { mail.push({ kind: 'account', ...item }); } });
  account = createAccountNodeHandler({ handle: service.handle, origin, env: {} });
  people = createAccountNodeHandler({ handle:createPublicProfileHandler({pool,enabled:true}), origin, env:{} });
  const interest = createInterestHandlers({ env: { PRO_INTEREST_ENABLED: 'true', EXP_INTEREST_DATABASE_URL: databaseURL,
    RESEND_API_KEY: 'capture-only', SIGNUP_FROM_EMAIL: 'EXP <fixture@example.test>', INTEREST_PUBLIC_ORIGIN: origin },
    storeFactory: () => createInterestStore(pool), mailer: async (config, email, links) => { mail.push({ kind: 'interest', email, ...links }); },
    erasureMailer: async (config, email, links) => { mail.push({ kind: 'erasure', email, ...links }); } });
  routes = { '/api/pro-interest': interest.request, '/api/confirm-interest': interest.confirm, '/api/withdraw-interest': interest.withdraw,
    '/api/request-interest-erasure': interest.requestErasure, '/api/delete-interest': interest.erase };
  return { origin, mail, errors,
    async resetIPWindow() { await pool.query('DELETE FROM exp_member_rate_limit'); },
    async expireCode(email) { await pool.query('UPDATE exp_member_verification SET "expiresAt"=now()-interval \'1 second\' WHERE identifier=$1', [`sign-in-otp-${email}`]); },
    async close() { await new Promise(resolve => server.close(resolve)); await pool.end(); } };
}
