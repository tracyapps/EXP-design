import { createHash, randomBytes } from 'node:crypto';
import pg from 'pg';

export const hashToken = token => createHash('sha256').update(token).digest('hex');
export const validToken = token => typeof token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(token);

// One SQL statement owns each transition. In particular, confirmation consumes
// the token in the same write that establishes confirmed permission.
export function createInterestStore(pool) {
  return {
    async accountStatus(reference, verifiedEmail) {
      const result = await pool.query(`SELECT model_preference, offer_version, consent_version, confirmed_at, withdrawn_at
        FROM exp_pro_interest WHERE withdrawal_hash=$1 AND email=$2`, [reference, verifiedEmail]);
      return result.rows[0] ?? null;
    },
    async withdrawAccount(reference, verifiedEmail) {
      const result = await pool.query(`UPDATE exp_pro_interest SET withdrawn_at=COALESCE(withdrawn_at,now()), token_hash=NULL
        WHERE withdrawal_hash=$1 AND email=$2 RETURNING email`, [reference, verifiedEmail]);
      return result.rowCount === 1;
    },
    async request(email, model) {
      const token = randomBytes(32).toString('base64url');
      const withdrawal = randomBytes(32).toString('base64url');
      const result = await pool.query(`
        INSERT INTO exp_pro_interest
          (email, model_preference, offer_version, consent_version, source, expires_at, token_hash, withdrawal_hash)
        VALUES ($1, $2, 'pro-discovery-v1', 'pro-interest-v1', 'pro page', now() + interval '24 hours', $3, $4)
        ON CONFLICT (email) DO UPDATE SET
          model_preference = EXCLUDED.model_preference, requested_at = now(),
          retry_after = now() + interval '10 minutes',
          expires_at = EXCLUDED.expires_at, token_hash = EXCLUDED.token_hash,
          withdrawal_hash = EXCLUDED.withdrawal_hash, confirmed_at = NULL, withdrawn_at = NULL,
          erasure_hash = NULL, erasure_expires_at = NULL, erasure_retry_after = NULL
        WHERE (exp_pro_interest.confirmed_at IS NULL OR exp_pro_interest.withdrawn_at IS NOT NULL)
          AND exp_pro_interest.retry_after <= now()
        RETURNING email`, [email, model, hashToken(token), hashToken(withdrawal)]);
      return result.rowCount ? { token, withdrawal } : null;
    },
    async deliveryFailed(email, token) {
      // Only reset this request. A later replacement/confirmation is untouched.
      await pool.query(`UPDATE exp_pro_interest SET token_hash = NULL,
        retry_after = now()
        WHERE email = $1 AND token_hash = $2 AND confirmed_at IS NULL`, [email, hashToken(token)]);
    },
    async confirm(token) {
      const result = await pool.query(`UPDATE exp_pro_interest
        SET confirmed_at = now(), token_hash = NULL
        WHERE token_hash = $1 AND expires_at > now()
          AND confirmed_at IS NULL AND withdrawn_at IS NULL RETURNING email`, [hashToken(token)]);
      return result.rowCount === 1;
    },
    async requestErasure(withdrawalToken) {
      const token = randomBytes(32).toString('base64url');
      const result = await pool.query(`UPDATE exp_pro_interest
        SET erasure_hash = $1, erasure_expires_at = now() + interval '15 minutes',
          erasure_retry_after = now() + interval '10 minutes'
        WHERE withdrawal_hash = $2 AND (erasure_retry_after IS NULL OR erasure_retry_after <= now())
        RETURNING email`, [hashToken(token), hashToken(withdrawalToken)]);
      return result.rowCount ? { email: result.rows[0].email, token } : null;
    },
    async erasureDeliveryFailed(token) {
      await pool.query(`UPDATE exp_pro_interest SET erasure_hash = NULL,
        erasure_expires_at = NULL, erasure_retry_after = now()
        WHERE erasure_hash = $1`, [hashToken(token)]);
    },
    async erase(token) {
      const result = await pool.query(`DELETE FROM exp_pro_interest
        WHERE erasure_hash = $1 AND erasure_expires_at > now() RETURNING email`, [hashToken(token)]);
      return result.rowCount === 1;
    },
    async withdraw(token) {
      const result = await pool.query(`UPDATE exp_pro_interest
        SET withdrawn_at = COALESCE(withdrawn_at, now()), token_hash = NULL
        WHERE withdrawal_hash = $1 RETURNING email`, [hashToken(token)]);
      return result.rowCount === 1;
    },
  };
}

let pool;
export function configuredStore(connectionString) {
  pool ??= new pg.Pool({ connectionString, max: 2, connectionTimeoutMillis: 3000,
    idleTimeoutMillis: 10000, statement_timeout: 5000, allowExitOnIdle: true });
  // Pool errors may contain credentials/addresses. Keep operational logs generic.
  if (pool.listenerCount('error') === 0) pool.on('error', () => console.warn('interest database unavailable'));
  return createInterestStore(pool);
}
