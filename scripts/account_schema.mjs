// Read-only schema generation against a disposable, empty local database.
import pg from 'pg';
import { randomBytes } from 'node:crypto';
import { getMigrations } from 'better-auth/db/migration';
import { createAccountService } from '../server/accounts/service.js';
const url = process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
if (!new URL(url).searchParams.get('host')?.startsWith('/tmp/exp-account-test.')) throw new Error('Isolated database required');
const pool = new pg.Pool({ connectionString: url });
try {
  const service = createAccountService({ pool, origin: 'http://127.0.0.1:5191', secret: randomBytes(32).toString('hex'), sendOTP: async () => {} });
  const migrations = await getMigrations(service.options);
  console.log(await migrations.compileMigrations());
} finally { await pool.end(); }
