import pg from 'pg';
import { isIP } from 'node:net';
import { toNodeHandler } from 'better-auth/node';
import { createAccountService } from './service.js';
import { interestConfiguration } from '../interest/handlers.js';
import { configuredStore } from '../interest/store.js';
import { createPublicProfileHandler } from './community.js';

export function accountConfiguration(env) {
  const origin = env.ACCOUNT_PUBLIC_ORIGIN;
  let url; try { url = new URL(origin); } catch { return null; }
  if (url.origin !== origin || (url.protocol !== 'https:' && !(env.NODE_ENV !== 'production' && url.hostname === '127.0.0.1'))) return null;
  if (!env.EXP_ACCOUNT_DATABASE_URL || !env.BETTER_AUTH_SECRET || env.BETTER_AUTH_SECRET.length < 32) return null;
  let database; try { database = new URL(env.EXP_ACCOUNT_DATABASE_URL); } catch { return null; }
  if (!['postgres:', 'postgresql:'].includes(database.protocol)) return null;
  if (env.NODE_ENV === 'production' && database.searchParams.get('sslmode') !== 'verify-full') return null;
  return { origin, secret: env.BETTER_AUTH_SECRET, databaseURL: env.EXP_ACCOUNT_DATABASE_URL };
}

export function accountInterestConfiguration(env, accountOrigin) {
  const config = interestConfiguration(env, 'withdraw');
  if (!config || config.origin !== accountOrigin) return null;
  try {
    const database = new URL(config.databaseURL);
    if (!['postgres:', 'postgresql:'].includes(database.protocol) ||
        (env.NODE_ENV === 'production' && database.searchParams.get('sslmode') !== 'verify-full')) return null;
    return config;
  } catch { return null; }
}

export function createAccountNodeHandler({ handle, origin, env = process.env }) {
  // Never trust a caller-supplied IP header. Vercel overwrites this platform
  // header; direct local previews instead use the actual connection address.
  const nodeHandler = toNodeHandler(handle);
  return async (request, response) => {
    const candidate = env.VERCEL === '1' ? request.headers['x-vercel-forwarded-for'] : request.socket?.remoteAddress;
    request.headers['x-exp-client-ip'] = typeof candidate === 'string' && isIP(candidate) ? candidate : '';
    // Configured origin, rather than Host/forwarded-proto, supplies library URLs.
    request.headers.host = new URL(origin).host;
    request.headers['x-forwarded-proto'] = new URL(origin).protocol.slice(0, -1);
    try { await nodeHandler(request, response); }
    catch { response.writeHead(503, { 'Cache-Control': 'no-store', 'Content-Type': 'application/json' }).end(JSON.stringify({ error: 'Account service is unavailable.' })); }
  };
}

let runtime;
let publicRuntime;
function accountPool(config) {
  const pool = new pg.Pool({ connectionString: config.databaseURL, max: 2, connectionTimeoutMillis: 3000, statement_timeout: 5000, allowExitOnIdle: true });
  pool.on('error', () => console.error('Account database connection failed.'));
  return pool;
}
export async function publicProfileEndpoint(request, response) {
  if (process.env.ACCOUNT_COMMUNITY_ENABLED !== 'true') {
    response.writeHead(404, { 'Content-Type':'application/json', 'Cache-Control':'no-store', 'Referrer-Policy':'no-referrer', 'X-Robots-Tag':'noindex' }).end(JSON.stringify({ error:'Profile not found.' }));
    return;
  }
  const config = accountConfiguration(process.env);
  if (!config) {
    response.writeHead(503, { 'Content-Type':'application/json', 'Cache-Control':'no-store' }).end(JSON.stringify({ error:'Community profiles are unavailable.' }));
    return;
  }
  publicRuntime ??= createAccountNodeHandler({ origin:config.origin, handle:createPublicProfileHandler({ pool:accountPool(config), enabled:true }) });
  await publicRuntime(request, response);
}
export default async function accountEndpoint(request, response) {
  const env = process.env;
  const config = accountConfiguration(env);
  if (!config) {
    response.writeHead(503, { 'Cache-Control': 'no-store', 'Content-Type': 'application/json' }).end(JSON.stringify({ error: 'Free accounts are not open yet.' }));
    return;
  }
  if (!runtime) {
    const pool = accountPool(config);
    const interestConfig = accountInterestConfiguration(env, config.origin);
    const service = createAccountService({ pool, ...config, registrationEnabled: env.ACCOUNTS_ENABLED === 'true',
      interestStore: interestConfig ? configuredStore(interestConfig.databaseURL) : null,
      proLinkEnabled: env.ACCOUNT_PRO_LINK_ENABLED === 'true',
      communityEnabled: env.ACCOUNT_COMMUNITY_ENABLED === 'true',
      newsEnabled: env.ACCOUNT_NEWS_ENABLED === 'true', ticketsEnabled: env.ACCOUNT_TICKETS_ENABLED === 'true',
      ticketMailEnabled: env.ACCOUNT_TICKET_MAIL_ENABLED === 'true',
      engagementEnabled: env.ACCOUNT_ENGAGEMENT_ENABLED === 'true',
      betaEnabled: env.ACCOUNT_BETA_ENABLED === 'true', async sendOTP({ email, otp }) {
      if (!env.RESEND_API_KEY || !env.SIGNUP_FROM_EMAIL) throw new Error('Account mail unavailable');
      const result = await fetch('https://api.resend.com/emails', { method: 'POST',
        signal: AbortSignal.timeout(5000), headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: env.SIGNUP_FROM_EMAIL, to: email, subject: 'Your EXP account code',
          text: `Your EXP account code is ${otp}. It expires in five minutes and can be used once. If you did not request it, ignore this email. This email does not subscribe you to updates or Pro offers.` }) });
      const receipt = await result.json().catch(() => null);
      if (!result.ok || typeof receipt?.id !== 'string' || !receipt.id) throw new Error('Account mail failed');
    } });
    runtime = createAccountNodeHandler({ handle: service.handle, origin: config.origin });
  }
  await runtime(request, response);
}
