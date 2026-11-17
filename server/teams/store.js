import pg from 'pg';
import { randomBytes } from 'node:crypto';
import { hashToken } from '../interest/store.js';

export function createTeamStore(pool) {
  return {
    async budget(key, maximum, seconds) {
      const result = await pool.query(`INSERT INTO exp_team_research_limit(key) VALUES($1)
        ON CONFLICT(key) DO UPDATE SET
          count=CASE WHEN exp_team_research_limit.started_at < now()-make_interval(secs=>$3) THEN 1 ELSE exp_team_research_limit.count+1 END,
          started_at=CASE WHEN exp_team_research_limit.started_at < now()-make_interval(secs=>$3) THEN now() ELSE exp_team_research_limit.started_at END
        WHERE exp_team_research_limit.count < $2 OR exp_team_research_limit.started_at < now()-make_interval(secs=>$3)
        RETURNING key`, [key, maximum, seconds]);
      return result.rowCount === 1;
    },
    async save(token, answers) {
      // Retrying a timed-out request cannot duplicate or replace an answer.
      await pool.query(`INSERT INTO exp_team_research(capability_hash,answers) VALUES($1,$2)
        ON CONFLICT(capability_hash) DO NOTHING`, [hashToken(token), answers]);
      const result = await pool.query(`SELECT answers=$2::jsonb AS same FROM exp_team_research WHERE capability_hash=$1 AND expires_at>now()`, [hashToken(token), answers]);
      return result.rowCount ? (result.rows[0].same ? 'saved' : 'already_saved') : 'expired';
    },
    async contact(capability, email) {
      const confirmation = randomBytes(32).toString('base64url');
      const result = await pool.query(`UPDATE exp_team_research SET email=$2,
        consent_version='team-research-contact-v1', requested_at=now(), confirmation_hash=$3,
        confirmation_expires_at=now()+interval '24 hours',retry_after=now()+interval '10 minutes'
        WHERE capability_hash=$1 AND expires_at>now() AND confirmed_at IS NULL
          AND (retry_after IS NULL OR retry_after<=now()) RETURNING capability_hash`,
      [hashToken(capability), email, hashToken(confirmation)]);
      return result.rowCount ? confirmation : null;
    },
    async deliveryFailed(confirmation) {
      await pool.query(`UPDATE exp_team_research SET email=NULL,consent_version=NULL,
        confirmation_hash=NULL,confirmation_expires_at=NULL,retry_after=now()
        WHERE confirmation_hash=$1 AND confirmed_at IS NULL`, [hashToken(confirmation)]);
    },
    async confirm(confirmation) {
      const result = await pool.query(`UPDATE exp_team_research SET confirmed_at=now(),confirmation_hash=NULL,
        confirmation_expires_at=NULL WHERE confirmation_hash=$1 AND confirmation_expires_at>now()
        AND expires_at>now() AND confirmed_at IS NULL RETURNING capability_hash`, [hashToken(confirmation)]);
      return result.rowCount === 1;
    },
    async withdraw(capability) {
      await pool.query(`UPDATE exp_team_research SET email=NULL,consent_version=NULL,confirmed_at=NULL,
        confirmation_hash=NULL,confirmation_expires_at=NULL,requested_at=NULL
        WHERE capability_hash=$1`, [hashToken(capability)]);
    },
    async erase(capability) {
      await pool.query('DELETE FROM exp_team_research WHERE capability_hash=$1', [hashToken(capability)]);
    },
  };
}
let pool;
export function configuredTeamStore(connectionString) {
  pool ??= new pg.Pool({connectionString,max:2,connectionTimeoutMillis:3000,idleTimeoutMillis:10000,statement_timeout:5000,allowExitOnIdle:true});
  if (!pool.listenerCount('error')) pool.on('error', () => console.warn('Team research database unavailable'));
  return createTeamStore(pool);
}
