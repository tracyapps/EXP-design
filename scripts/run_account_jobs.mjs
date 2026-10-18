// Private operator/scheduler entry point. No public HTTP route, raw identifiers,
// provider errors or credentials in output. No implicit .env loading.
import pg from 'pg';
import { accountRetention,accountRetentionVersion } from '../server/accounts/retention.js';
import { processTicketMail,createTicketMailer } from '../server/accounts/ticket-mail.js';

const args=process.argv.slice(2);
const allowed=['--mail',`--purge=${accountRetentionVersion}`,'--preview'];
if(args.some(arg=>!allowed.includes(arg)) || new Set(args).size!==args.length || (args.includes('--preview') && args.length>1)) {
  console.error('Use --preview (default), --mail, and/or --purge=member-retention-v1');process.exit(1);
}
let pool;
try {
  const url=new URL(process.env.EXP_ACCOUNT_JOBS_DATABASE_URL);
  const local=process.env.NODE_ENV!=='production' && url.searchParams.get('host')?.startsWith('/tmp/exp-account-test.');
  if(!['postgres:','postgresql:'].includes(url.protocol) || (!local && url.searchParams.get('sslmode')!=='verify-full'))throw new Error('Invalid storage');
  pool=new pg.Pool({connectionString:url.href,max:2,connectionTimeoutMillis:3000,statement_timeout:10000,allowExitOnIdle:true});
  pool.on('error',()=>{process.exitCode=1;console.error('Account job storage unavailable');});
  if(!args.length || args.includes('--preview')) {
    const retention=await accountRetention({pool});
    const queue=(await pool.query('SELECT state,count(*)::integer AS count FROM exp_member_ticket_mail GROUP BY state ORDER BY state')).rows;
    console.log(JSON.stringify({retention,queue}));
  }
  if(args.includes('--mail')) {
    if(process.env.ACCOUNT_TICKET_MAIL_ENABLED!=='true' || !process.env.RESEND_API_KEY || !process.env.SIGNUP_FROM_EMAIL)throw new Error('Mail paused');
    const ticketMail=await processTicketMail({pool,enabled:true,origin:process.env.ACCOUNT_PUBLIC_ORIGIN,
      from:process.env.SIGNUP_FROM_EMAIL,send:createTicketMailer({apiKey:process.env.RESEND_API_KEY})});
    console.log(JSON.stringify({ticketMail}));
    if(ticketMail.failed>0)process.exitCode=1;
  }
  if(args.includes(`--purge=${accountRetentionVersion}`))console.log(JSON.stringify({retention:await accountRetention({pool,apply:true,
    enabled:process.env.ACCOUNT_RETENTION_ENABLED==='true',policy:accountRetentionVersion})}));
} catch {process.exitCode=1;console.error('Account job failed; check private configuration and storage. No success is assumed.');}
finally{try{await pool?.end();}catch{process.exitCode=1;console.error('Account job connection close failed');}}
