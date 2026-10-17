import pg from 'pg';

const names = new Set(['eligible_first_run', 'work_started', 'work_edited', 'output_completed', 'activation_completed', 'active_day']);
const sources = new Set(['new', 'opened', 'svg', 'image', 'pdf', 'xd', 'figma', 'html', 'codepen', 'storybook']);
const outputs = new Set(['png', 'jpg', 'pdf', 'svg', 'batch', 'handoff', 'html', 'tokens', 'codepen_launcher']);
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const exactKeys = (value, allowed) => Object.keys(value).every(key => allowed.includes(key));

export function validateUsage(body, now = new Date()) {
  if (Buffer.byteLength(typeof body === 'string' ? body : JSON.stringify(body) ?? '') > 16384) return null;
  const data = typeof body === 'string' ? JSON.parse(body) : body;
  if (!object(data) || !exactKeys(data, ['schemaVersion', 'consentVersion', 'installID', 'events']) ||
      data.schemaVersion !== 1 || data.consentVersion !== 'usage-v1' || !uuid(data.installID) ||
      !Array.isArray(data.events) || data.events.length < 1 || data.events.length > 32) return null;
  for (const event of data.events) {
    if (!object(event) || !exactKeys(event, ['id', 'name', 'day', 'appVersion', 'osMajor', 'source', 'output']) ||
        !uuid(event.id) || !names.has(event.name) ||
        typeof event.day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(event.day) ||
        typeof event.appVersion !== 'string' || !/^\d{1,3}\.\d{1,3}$/.test(event.appVersion) ||
        !Number.isInteger(event.osMajor) || event.osMajor < 1 || event.osMajor > 99) return null;
    const day = new Date(`${event.day}T00:00:00Z`);
    if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== event.day ||
        now - day > 8 * 86400000 || day - now > 86400000) return null;
    const needsSource = ['work_started', 'work_edited', 'output_completed'].includes(event.name);
    if (needsSource ? !sources.has(event.source) : event.source !== undefined) return null;
    if (event.name === 'output_completed' ? !outputs.has(event.output) : event.output !== undefined) return null;
  }
  return data;
}

export function usageStore(pool) {
  return {
    async accept(batch) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const budget = await client.query(`INSERT INTO exp_usage_limits (install_id, attempts) VALUES ($1, $2)
          ON CONFLICT (install_id, received_day) DO UPDATE SET attempts = exp_usage_limits.attempts + $2
          WHERE exp_usage_limits.attempts + $2 <= 256 RETURNING attempts`, [batch.installID, batch.events.length]);
        if (!budget.rowCount) { await client.query('ROLLBACK'); return false; }
        for (const event of batch.events) {
          await client.query(`INSERT INTO exp_usage_events
            (install_id,event_id,consent_version,event_name,event_day,app_version,os_major,source,output)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT DO NOTHING`,
          [batch.installID, event.id, batch.consentVersion, event.name, event.day,
            event.appVersion, event.osMajor, event.source ?? null, event.output ?? null]);
        }
        await client.query('COMMIT'); return true;
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    },
    async purge() {
      // A daily job prunes at 29 days, leaving a full day's margin under the
      // published 30-day live-store ceiling. Monitor missed runs before enablement.
      await pool.query("DELETE FROM exp_usage_events WHERE received_at <= now() - interval '29 days'");
      await pool.query("DELETE FROM exp_usage_limits WHERE received_day < CURRENT_DATE - 29");
    },
  };
}
let pool;
function configuredStore(connectionString) {
  pool ??= new pg.Pool({ connectionString, max: 2, connectionTimeoutMillis: 3000,
    idleTimeoutMillis: 10000, statement_timeout: 5000, allowExitOnIdle: true });
  if (!pool.listenerCount('error')) pool.on('error', () => console.warn('usage storage unavailable'));
  return usageStore(pool);
}
export function createUsageHandler({ env = process.env, storeFactory = configuredStore, now = () => new Date() } = {}) {
  return async function usage(request, response) {
    const end = (status, body = '') => { response.statusCode = status; response.end(body); };
    response.setHeader('cache-control', 'no-store');
    response.setHeader('referrer-policy', 'no-referrer');
    if (request.method !== 'POST') { response.setHeader('allow', 'POST'); return end(405); }
    // Both an operator switch and completed host/log/retention/abuse review are
    // required before enabling the endpoint. No credentials ever enter the app.
    if (env.EXP_USAGE_ENABLED !== 'true' || env.EXP_USAGE_HOST_VERIFIED !== 'true' || !env.EXP_USAGE_DATABASE_URL) return end(503);
    if (request.headers?.origin) return end(403); // Native collector, no browser/CORS intake.
    if (request.headers?.['content-type']?.split(';')[0].trim() !== 'application/json') return end(415);
    let batch;
    try { batch = validateUsage(request.body, now()); } catch { return end(400); }
    if (!batch) return end(400);
    try { return end(await storeFactory(env.EXP_USAGE_DATABASE_URL).accept(batch) ? 204 : 429); }
    catch { console.warn('usage collection unavailable'); return end(503); }
  };
}
