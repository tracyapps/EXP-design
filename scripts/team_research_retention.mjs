// Operator task; defaults to counts only. Never prints answers/email/capabilities.
import pg from 'pg';
if (!process.env.EXP_INTEREST_DATABASE_URL) throw new Error('EXP_INTEREST_DATABASE_URL required');
const pool=new pg.Pool({connectionString:process.env.EXP_INTEREST_DATABASE_URL,max:1});
try {
  const expired=(await pool.query('SELECT count(*)::int AS n FROM exp_team_research WHERE expires_at<=now()')).rows[0].n;
  const pending=(await pool.query('SELECT count(*)::int AS n FROM exp_team_research WHERE confirmed_at IS NULL AND email IS NOT NULL AND confirmation_expires_at<=now()')).rows[0].n;
  if(process.argv.includes('--apply')) {
    await pool.query('DELETE FROM exp_team_research WHERE expires_at<=now()');
    await pool.query('UPDATE exp_team_research SET email=NULL,consent_version=NULL,confirmation_hash=NULL,confirmation_expires_at=NULL WHERE confirmed_at IS NULL AND confirmation_expires_at<=now()');
    await pool.query("DELETE FROM exp_team_research_limit WHERE started_at<now()-interval '1 day'");
  }
  console.log(JSON.stringify({mode:process.argv.includes('--apply')?'apply':'preview',expiredResponses:expired,expiredContacts:pending}));
} finally {await pool.end();}
