import { createHmac } from 'node:crypto';
import { AsyncLocalStorage } from 'node:async_hooks';
import { betterAuth } from 'better-auth';
import { emailOTP } from 'better-auth/plugins';
import { APIError, createAuthMiddleware } from 'better-auth/api';
import { betaActions, handleBeta } from './beta.js';
import { proActions, handleAccountInterest } from './pro-interest.js';
import { communityActions, handleCommunity } from './community.js';
import { newsActions, handleNews } from './news.js';
import { ticketActions, handleTickets } from './tickets.js';

export const accountConsentVersion = 'free-account-v1';
const privateHeaders = { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Robots-Tag': 'noindex' };
const json = (body, status = 200, extra = {}) => {
  const headers = new Headers(extra);
  for (const [key, value] of Object.entries(privateHeaders)) headers.set(key, value);
  return Response.json(body, { status, headers });
};
const text = (value, max, required = false) => typeof value === 'string' && value.length <= max && (!required || value.trim().length > 0);

// Established library owns challenges, atomic OTP consumption, sessions and CSRF.
// The single public endpoint does not expose password/OAuth/admin/plugin routes.
export function createAccountService({ pool, origin, secret, sendOTP, registrationEnabled = true, betaEnabled = false,
  interestStore = null, proLinkEnabled = false, communityEnabled = false, newsEnabled = false, ticketsEnabled = false }) {
  const delivery = new AsyncLocalStorage();
  const auth = betterAuth({
    appName: 'EXP [design]', baseURL: origin, basePath: '/api/auth', secret,
    database: pool, telemetry: { enabled: false }, logger: { disabled: true },
    trustedOrigins: [origin],
    advanced: { useSecureCookies: origin.startsWith('https:'), cookiePrefix: 'exp-member',
      database: { generateId: 'uuid' }, ipAddress: { ipAddressHeaders: ['x-exp-client-ip'] } },
    session: { modelName: 'exp_member_session', expiresIn: 60 * 60 * 24 * 7,
      updateAge: 60 * 60 * 24, freshAge: 300, cookieCache: { enabled: false } },
    account: { modelName: 'exp_member_identity' },
    verification: { modelName: 'exp_member_verification' },
    user: { modelName: 'exp_member_user', deleteUser: { enabled: true },
      additionalFields: {
        bio: { type: 'string', required: false, defaultValue: '' },
        link: { type: 'string', required: false, defaultValue: '' },
        largeText: { type: 'boolean', required: false, defaultValue: false },
        profileVisibility: { type: 'string', required: false, defaultValue: 'private', input: false },
        accountConsentVersion: { type: 'string', required: false, input: false },
        accountAcceptedAt: { type: 'date', required: false, input: false }
      } },
    rateLimit: { enabled: true, storage: 'database', modelName: 'exp_member_rate_limit', window: 60, max: 60 },
    plugins: [emailOTP({ otpLength: 6, expiresIn: 300, allowedAttempts: 5,
      storeOTP: { hash: async otp => createHmac('sha256', secret).update(`account-otp:${otp}`).digest('hex') },
      resendStrategy: 'rotate', rateLimit: { window: 60, max: 5 },
      async sendVerificationOTP({ email, otp, type }) {
        if (type !== 'sign-in') throw new Error('Unsupported mail purpose');
        try { await sendOTP({ email, otp }); }
        catch (error) {
          // Better Auth logs and absorbs this callback's rejection. Preserve
          // failure per request so our UI cannot report that mail was sent.
          const requestDelivery = delivery.getStore();
          if (requestDelivery) requestDelivery.failed = true;
          throw error;
        }
      } })],
    hooks: { before: createAuthMiddleware(async ctx => {
      if (ctx.path !== '/email-otp/send-verification-otp') return;
      const email = ctx.body.email.toLowerCase();
      // Shared per-address cooldown and hourly cap, before OTP rotation/mail.
      const key = createHmac('sha256', secret).update(`account-mail:${email}`).digest('hex');
      const result = await pool.query(`INSERT INTO exp_member_mail_limit (key, sent_at, window_start, count)
        VALUES ($1, now(), now(), 1) ON CONFLICT (key) DO UPDATE SET sent_at = now(),
        window_start = CASE WHEN exp_member_mail_limit.window_start <= now() - interval '1 hour' THEN now() ELSE exp_member_mail_limit.window_start END,
        count = CASE WHEN exp_member_mail_limit.window_start <= now() - interval '1 hour' THEN 1 ELSE exp_member_mail_limit.count + 1 END
        WHERE exp_member_mail_limit.sent_at <= now() - interval '60 seconds'
        AND (exp_member_mail_limit.window_start <= now() - interval '1 hour' OR exp_member_mail_limit.count < 5)
        RETURNING key`, [key]);
      if (!result.rowCount) throw new APIError('TOO_MANY_REQUESTS', { message: 'Please wait before requesting another code.' });
    }) },
    databaseHooks: { user: { create: { before: async (user, ctx) => {
      if (!registrationEnabled || ctx?.path !== '/sign-in/email-otp' || ctx.body.accountConsent !== true ||
          ctx.body.consentVersion !== accountConsentVersion) {
        throw new APIError('BAD_REQUEST', { message: 'Choose Create account to register.' });
      }
      return { data: { ...user, profileVisibility: 'private', accountConsentVersion,
        accountAcceptedAt: new Date(), bio: '', link: '', largeText: false } };
    } } } }
  });

  async function handleRequest(request) {
    try {
      const url = new URL(request.url);
      if (url.pathname !== '/api/account') return json({ error: 'Not found.' }, 404);
      if (!['GET', 'POST'].includes(request.method)) return json({ error: 'Use GET or POST.' }, 405, { Allow: 'GET, POST' });
      if (request.headers.get('sec-fetch-site') === 'cross-site' ||
          (request.headers.has('origin') && request.headers.get('origin') !== origin) ||
          (request.method === 'POST' && request.headers.get('origin') !== origin)) return json({ error: 'This request is not allowed.' }, 403);
      if (!request.headers.get('x-exp-client-ip')) return json({ error: 'Account service is unavailable.' }, 503);
      let action = 'session', body = {};
      if (request.method === 'POST') {
        if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') return json({ error: 'Use JSON.' }, 415);
        const reader = request.body?.getReader();
        const chunks = []; let size = 0;
        if (reader) for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > 12288) { await reader.cancel(); return json({ error: 'Request is too large.' }, 413); }
          chunks.push(value);
        }
        const raw = Buffer.concat(chunks).toString('utf8');
        body = JSON.parse(raw);
        if (!body || typeof body !== 'object' || Array.isArray(body)) return json({ error: 'Invalid request.' }, 400);
        action = body.action;
        if (size > 4096 && !['create-ticket','reply-ticket'].includes(action)) return json({ error: 'Request is too large.' }, 413);
      }
      const allowed = {
        ...betaActions, ...proActions, ...communityActions, ...newsActions, ...ticketActions, session: [], 'send-code': ['email'],
        'verify-code': ['email', 'otp', 'intent', 'name', 'accountConsent', 'consentVersion'],
        'save-profile': ['name', 'bio', 'link'], 'save-preferences': ['largeText'],
        'sign-out': [], 'sign-out-all': [], 'delete-account': ['confirmation']
      };
      if (typeof action !== 'string' || !Object.hasOwn(allowed, action) || Object.keys(body).some(k => k !== 'action' && !allowed[action].includes(k))) return json({ error: 'Invalid account action or field.' }, 400);
      if (Object.hasOwn(betaActions, action) || Object.hasOwn(proActions, action) || Object.hasOwn(communityActions, action) || Object.hasOwn(newsActions, action) || Object.hasOwn(ticketActions, action)) {
        // Same database-backed auth/abuse checks as the existing account actions.
        const session = await auth.handler(new Request(`${origin}/api/auth/get-session`, { headers: request.headers }));
        const member = (await session.json().catch(() => null))?.user;
        const headers = new Headers();
        for (const cookie of session.headers.getSetCookie()) headers.append('set-cookie', cookie);
        if (!session.ok) return json({ error: session.status === 429 ? 'Please wait before trying again.' : 'Account service is unavailable. Please try later.' }, session.status, headers);
        if (!member?.id || member.emailVerified !== true) return json({ error: 'Please sign in again.' }, 401, headers);
        const response = Object.hasOwn(betaActions, action)
          ? await handleBeta({ pool, userId: member.id, body, enabled: betaEnabled })
          : Object.hasOwn(proActions, action)
            ? await handleAccountInterest({ pool, user: member, body, interestStore, enabled: proLinkEnabled })
            : Object.hasOwn(communityActions, action)
              ? await handleCommunity({ pool, userId: member.id, body, enabled: communityEnabled })
              : Object.hasOwn(newsActions, action)
                ? await handleNews({ pool, userId: member.id, body, enabled: newsEnabled })
                : await handleTickets({ pool, userId: member.id, body, enabled: ticketsEnabled });
        return json(response.body, response.status, headers);
      }
      let path, payload;
      if (action === 'session') { path = '/get-session'; }
      else if (['send-code', 'verify-code'].includes(action)) {
        if (!text(body.email, 254, true) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)) return json({ error: 'Enter a valid email address.' }, 400);
        payload = { email: body.email.trim().toLowerCase() };
        if (action === 'send-code') { path = '/email-otp/send-verification-otp'; payload.type = 'sign-in'; }
        else {
          if (!/^\d{6}$/.test(body.otp) || !['sign-in', 'register'].includes(body.intent)) return json({ error: 'Enter the six-digit code and choose sign in or create account.' }, 400);
          if (body.intent === 'register' && (!text(body.name, 80, true) || body.accountConsent !== true || body.consentVersion !== accountConsentVersion)) return json({ error: 'Enter your display name and confirm account creation.' }, 400);
          path = '/sign-in/email-otp';
          Object.assign(payload, { otp: body.otp, name: body.intent === 'register' ? body.name.trim() : undefined,
            accountConsent: body.intent === 'register' && body.accountConsent === true, consentVersion: body.consentVersion });
        }
      } else if (action === 'save-profile') {
        if (!text(body.name, 80, true) || !text(body.bio, 500) || !text(body.link, 300)) return json({ error: 'Check the profile fields and their length limits.' }, 400);
        if (body.link) {
          let link; try { link = new URL(body.link); } catch { return json({ error: 'Use a complete HTTPS link or leave it empty.' }, 400); }
          if (link.protocol !== 'https:' || link.username || link.password) return json({ error: 'Use a complete HTTPS link without login details.' }, 400);
        }
        path = '/update-user'; payload = { name: body.name.trim(), bio: body.bio.trim(), link: body.link.trim() };
      } else if (action === 'save-preferences') {
        if (typeof body.largeText !== 'boolean') return json({ error: 'Choose a text size.' }, 400);
        path = '/update-user'; payload = { largeText: body.largeText };
      } else if (action === 'delete-account') {
        if (body.confirmation !== 'DELETE') return json({ error: 'Type DELETE to confirm.' }, 400);
        path = '/delete-user'; payload = {};
      } else { path = action === 'sign-out-all' ? '/revoke-sessions' : '/sign-out'; payload = {}; }

      const headers = new Headers(request.headers);
      headers.set('content-type', 'application/json');
      headers.delete('content-length');
      const response = await auth.handler(new Request(`${origin}/api/auth${path}`, {
        method: payload ? 'POST' : 'GET', headers, body: payload ? JSON.stringify(payload) : undefined
      }));
      const result = await response.json().catch(() => null);
      if (action === 'send-code' && delivery.getStore()?.failed) return json({ error: 'Could not send a code. Please try again later.' }, 503);
      const cookies = response.headers.getSetCookie();
      const outputHeaders = new Headers(privateHeaders);
      for (const cookie of cookies) outputHeaders.append('set-cookie', cookie);
      if (!response.ok) {
        const error = response.status === 429 ? 'Please wait before trying again.' : response.status >= 500 ? 'Account service is unavailable. Please try later.' :
          result?.code === 'SESSION_EXPIRED' ? 'Sign out and sign in with a fresh code, then retry within five minutes.' :
          response.status === 401 ? 'Please sign in again.' : 'Could not complete that action. Check your code and account-creation choice, or request a fresh code.';
        return json({ error }, response.status, outputHeaders);
      }
      if (action === 'session') {
        const user = result?.user;
        // Never return bearer/session tokens, IPs or user-agent details to JS.
        return json({ ok: true, registrationOpen: registrationEnabled, user: user ? { id: user.id, email: user.email, name: user.name,
          bio: user.bio || '', link: user.link || '', largeText: user.largeText === true,
          profileVisibility: 'private' } : null }, 200, outputHeaders);
      }
      return json({ ok: true }, 200, outputHeaders);
    } catch (error) {
      return json({ error: error instanceof SyntaxError ? 'Invalid JSON.' : 'Account service is unavailable. Please try later.' }, error instanceof SyntaxError ? 400 : 503);
    }
  }
  const handle = request => delivery.run({ failed: false }, () => handleRequest(request));
  return { handle, options: auth.options };
}
