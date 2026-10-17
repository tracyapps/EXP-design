// Private operator job. Schedule daily and retain its successful job receipt
// before enabling collection. It prints no identifiers or connection details.
import pg from 'pg';
import { usageStore } from '../server/usage/collector.js';
if (!process.env.EXP_USAGE_DATABASE_URL) throw new Error('Usage storage is not configured');
const pool = new pg.Pool({ connectionString: process.env.EXP_USAGE_DATABASE_URL, max: 1 });
pool.on('error', () => { process.exitCode = 1; console.error('Usage retention storage unavailable'); });
try { await usageStore(pool).purge(); console.log('Usage retention purge complete'); }
catch { process.exitCode = 1; console.error('Usage retention purge failed'); }
finally { await pool.end(); }
