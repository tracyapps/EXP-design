import { configuredStore, validToken } from './store.js';

export function sendJson(response, body, status = 200) {
  response.statusCode = status;
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('cache-control', 'no-store');
  response.setHeader('referrer-policy', 'no-referrer');
  response.end(JSON.stringify(body));
}

function payloadOf(request) {
  const raw = request.body;
  if (typeof raw === 'string' && raw.length > 2048) throw new Error('invalid request');
  const payload = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('invalid request');
  return payload;
}

export function interestConfiguration(env, operation = 'request') {
  if (!env.EXP_INTEREST_DATABASE_URL || !env.INTEREST_PUBLIC_ORIGIN ||
      (['request', 'confirm'].includes(operation) && env.PRO_INTEREST_ENABLED !== 'true') ||
      (['request', 'requestErasure'].includes(operation) && (!env.RESEND_API_KEY || !env.SIGNUP_FROM_EMAIL))) return null;
  try {
    const origin = new URL(env.INTEREST_PUBLIC_ORIGIN);
    const local = env.NODE_ENV !== 'production' && ['localhost', '127.0.0.1'].includes(origin.hostname);
    if ((!local && origin.protocol !== 'https:') || !['http:', 'https:'].includes(origin.protocol) ||
        origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash) return null;
    return { origin: origin.origin, apiKey: env.RESEND_API_KEY, from: env.SIGNUP_FROM_EMAIL,
      databaseURL: env.EXP_INTEREST_DATABASE_URL };
  } catch { return null; }
}

async function sendEmail(config, email, subject, text) {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${config.apiKey}`, 'content-type': 'application/json' },
    signal: AbortSignal.timeout(5000),
    body: JSON.stringify({ from: config.from, to: email, subject, text }),
  });
  if (!response.ok) throw new Error('confirmation delivery failed');
  const sent = await response.json();
  if (typeof sent?.id !== 'string' || !sent.id) throw new Error('invalid delivery response');
}

async function sendConfirmation(config, email, links) {
  // Fragments stay out of HTTP access logs. GET never changes permission;
  // the destination requires an explicit button press and POST.
  await sendEmail(config, email, 'Confirm your interest in EXP Pro',
    `You requested updates and a feedback invitation about the proposed EXP Pro offer.\n\nConfirm within 24 hours:\n${links.confirm}\n\nThis does not join the release list or a general marketing list. No payment is taken.\n\nCancel this request or withdraw Pro interest at any time:\n${links.withdraw}\n\nIf you did not request this, ignore this email. You will not be enrolled without confirmation.`);
}

async function sendErasure(config, email, links) {
  await sendEmail(config, email, 'Confirm deletion of your EXP Pro-interest record',
    `A request was made to delete your live EXP Pro-interest signup record.\n\nOpen this link within 15 minutes, then press the deletion button:\n${links.erase}\n\nThis removes your email, payment-model preference and permission record from the live Pro-interest database. Any free-account connection becomes inactive; disconnect it in your account to remove that saved reference. Your release-list preference, free account and local design files are separate. Sent email, provider logs and backups follow their own retention rules.\n\nIf you did not request deletion, ignore this message. Opening the link alone does not delete anything.`);
}

export function createInterestHandlers({ env = process.env, storeFactory = configuredStore, mailer = sendConfirmation, erasureMailer = sendErasure } = {}) {
  async function prepare(request, response, operation) {
    if (request.method !== 'POST') {
      response.setHeader('allow', 'POST');
      sendJson(response, { error: 'method not allowed' }, 405); return null;
    }
    const config = interestConfiguration(env, operation);
    if (!config) { sendJson(response, { error: 'Pro interest signup is unavailable right now. Please try again later.' }, 503); return null; }
    if (request.headers?.origin !== config.origin) {
      sendJson(response, { error: 'invalid request origin' }, 403); return null;
    }
    try { return { config, payload: payloadOf(request) }; }
    catch { sendJson(response, { error: 'invalid request' }, 400); return null; }
  }
  return {
    async request(request, response) {
      const prepared = await prepare(request, response, 'request'); if (!prepared) return;
      const { config, payload } = prepared;
      if (typeof payload.website === 'string' && payload.website) return sendJson(response, { ok: true, state: 'pending' }, 202);
      if (typeof payload.email !== 'string' || payload.email.length > 254 ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(payload.email.trim()) ||
          !['one_time', 'subscription', 'either'].includes(payload.model) || payload.consent !== true ||
          payload.consentVersion !== 'pro-interest-v1' || payload.source !== 'pro page' ||
          (payload.website !== undefined && typeof payload.website !== 'string')) {
        return sendJson(response, { error: 'Enter a valid email, choose a payment preference and agree to the Pro-interest email permission.' }, 400);
      }
      const email = payload.email.trim().toLowerCase();
      try {
        const store = storeFactory(config.databaseURL);
        const pending = await store.request(email, payload.model);
        if (pending) {
          try {
            await mailer(config, email, {
              confirm: `${config.origin}/confirm-interest#${pending.token}`,
              withdraw: `${config.origin}/withdraw-interest#${pending.withdrawal}`,
            });
          } catch {
            await store.deliveryFailed(email, pending.token);
            throw new Error('mail unavailable');
          }
        }
        // Same response for a cooldown repeat or already-confirmed address.
        return sendJson(response, { ok: true, state: 'pending' }, 202);
      } catch {
        console.warn('Pro interest request unavailable');
        return sendJson(response, { error: 'Could not send confirmation. Please try again later.' }, 502);
      }
    },
    async confirm(request, response) {
      const prepared = await prepare(request, response, 'confirm'); if (!prepared) return;
      const { config, payload } = prepared;
      if (!validToken(payload.token)) return sendJson(response, { error: 'This confirmation link is invalid or expired. Request a new one.' }, 400);
      try {
        const confirmed = await storeFactory(config.databaseURL).confirm(payload.token);
        if (!confirmed) return sendJson(response, { error: 'This confirmation link was already used, cancelled or expired. You can request a new one.' }, 400);
        return sendJson(response, { ok: true, state: 'confirmed' });
      } catch {
        console.warn('Pro interest confirmation unavailable');
        return sendJson(response, { error: 'Could not confirm right now. Please try again later.' }, 502);
      }
    },
    async requestErasure(request, response) {
      const prepared = await prepare(request, response, 'requestErasure'); if (!prepared) return;
      const { config, payload } = prepared;
      if (!validToken(payload.token)) return sendJson(response, { error: 'Open the complete withdrawal link from your confirmation email.' }, 400);
      try {
        const store = storeFactory(config.databaseURL);
        const pending = await store.requestErasure(payload.token);
        if (pending) {
          try {
            await erasureMailer(config, pending.email, { erase: `${config.origin}/delete-interest#${pending.token}` });
          } catch {
            await store.erasureDeliveryFailed(pending.token);
            throw new Error('deletion mail unavailable');
          }
        }
        return sendJson(response, { ok: true, state: 'erasure_pending' }, 202);
      } catch {
        console.warn('Pro interest deletion request unavailable');
        return sendJson(response, { error: 'Could not send the deletion confirmation. Please try again later.' }, 502);
      }
    },
    async erase(request, response) {
      const prepared = await prepare(request, response, 'erase'); if (!prepared) return;
      const { config, payload } = prepared;
      if (!validToken(payload.token)) return sendJson(response, { error: 'This deletion link is invalid or expired.' }, 400);
      try {
        const erased = await storeFactory(config.databaseURL).erase(payload.token);
        if (!erased) return sendJson(response, { error: 'This deletion link was used, replaced or expired. Request a fresh link from your withdrawal page.' }, 400);
        return sendJson(response, { ok: true, state: 'erased' });
      } catch {
        console.warn('Pro interest deletion unavailable');
        return sendJson(response, { error: 'Could not delete the record right now. Please try again later.' }, 502);
      }
    },
    async withdraw(request, response) {
      const prepared = await prepare(request, response, 'withdraw'); if (!prepared) return;
      const { config, payload } = prepared;
      if (!validToken(payload.token)) return sendJson(response, { error: 'This withdrawal link is invalid.' }, 400);
      try {
        // Idempotent and generic; deletion/unknown record does not expose identity.
        await storeFactory(config.databaseURL).withdraw(payload.token);
        return sendJson(response, { ok: true, state: 'withdrawn' });
      } catch {
        console.warn('Pro interest withdrawal unavailable');
        return sendJson(response, { error: 'Could not withdraw right now. Please try again later.' }, 502);
      }
    },
  };
}
