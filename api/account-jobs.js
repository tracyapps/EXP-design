import pg from 'pg';
import {authorizedJob,createAccountJobHandler} from '../server/accounts/jobs.js';
import {createTicketMailer} from '../server/accounts/ticket-mail.js';

let pool;
export default async function accountJobs(request,response) {
  const env=process.env;
  // Authenticate before opening storage; no cookie/member/staff route can run jobs.
  if(!authorizedJob(request,env.EXP_ACCOUNT_JOB_TOKEN))return response.writeHead(401,{'Cache-Control':'no-store'}).end();
  let url;try{url=new URL(env.EXP_ACCOUNT_JOBS_DATABASE_URL);}catch{}
  if(!url || !['postgres:','postgresql:'].includes(url.protocol) || url.searchParams.get('sslmode')!=='verify-full')return response.writeHead(503,{'Cache-Control':'no-store'}).end();
  if(!pool){pool=new pg.Pool({connectionString:url.href,max:2,connectionTimeoutMillis:3000,statement_timeout:10000,allowExitOnIdle:true});pool.on('error',()=>console.error('Account job storage unavailable'));}
  return createAccountJobHandler({pool,env,send:createTicketMailer({apiKey:env.RESEND_API_KEY})})(request,response);
}
