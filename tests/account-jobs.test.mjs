import {before,beforeEach,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import http from 'node:http';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import pg from 'pg';
import {handleTickets} from '../server/accounts/tickets.js';
import {processTicketMail,createTicketMailer} from '../server/accounts/ticket-mail.js';
import {accountRetention,accountRetentionVersion} from '../server/accounts/retention.js';
import {createAccountJobHandler} from '../server/accounts/jobs.js';
import accountJobsEndpoint from '../api/account-jobs.js';

const db=process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
if(!db || !new URL(db).searchParams.get('host')?.startsWith('/tmp/exp-account-test.'))throw new Error('Disposable PostgreSQL required');
const operator=new pg.Pool({connectionString:db});
const url=new URL(db);url.pathname='/exp_account_jobs_test';
const pool=new pg.Pool({connectionString:url.href});
before(async()=>{
  await operator.query('CREATE DATABASE exp_account_jobs_test');
  for(const file of ['003_free_accounts.sql','005_member_beta.sql','007_community_profiles.sql','008_news_and_tickets.sql','009_ticket_mail_and_retention.sql'])
    await pool.query(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));
});
beforeEach(async()=>{await pool.query('TRUNCATE exp_member_user,exp_member_verification,exp_member_rate_limit,exp_member_mail_limit CASCADE');});
after(async()=>{await pool.end();await operator.end();});
async function member(staff=false){
  const id=randomUUID();
  await pool.query(`INSERT INTO exp_member_user(id,name,email,"emailVerified","profileVisibility") VALUES($1,'Private Name',$2,true,'private')`,[id,`${id}@example.test`]);
  if(staff)await pool.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES($1,'Isolated fixture')",[id]);
  return id;
}
async function action(userId,body,options={}){return handleTickets({pool,userId,body,enabled:true,mailEnabled:true,...options});}
async function open(author){const id=randomUUID();assert.equal((await action(author,{action:'create-ticket',id,subject:'Secret subject',message:'Secret message'})).status,200);return id;}
async function reply(actor,id,revision=1,receipt=randomUUID()){
  const payload={action:'reply-ticket',id,receipt,revision,message:'Secret reply'};
  assert.equal((await action(actor,payload)).status,200);return payload;
}
const worker=options=>processTicketMail({pool,enabled:true,origin:'https://accounts.example.test',from:'EXP <support@example.test>',send:async()=>randomUUID(),...options});
const rows=async()=> (await pool.query('SELECT * FROM exp_member_ticket_mail ORDER BY created_at,id')).rows;
async function due(){await pool.query("UPDATE exp_member_ticket_mail SET next_attempt_at=now()-interval '1 minute',lease_until=now()-interval '1 minute'");}

test('ticket and outbox commit together; repeated create/reply cannot duplicate notifications',async()=>{
  const author=await member(),staff=await member(true),id=randomUUID();
  const payload={action:'create-ticket',id,subject:'Secret subject',message:'Secret message'};
  const responses=await Promise.all(Array.from({length:4},()=>action(author,payload)));
  assert.ok(responses.every(r=>r.status===200));
  assert.equal((await rows()).length,1);assert.equal((await rows())[0].recipient_id,staff);
  const answer=await reply(staff,id);assert.equal((await action(staff,answer)).status,200);
  assert.equal((await rows()).length,2);assert.equal((await rows())[1].recipient_id,author);
  await reply(author,id,2);assert.equal((await rows()).length,3);
  const closed=await action(author,{action:'set-ticket-status',id,receipt:randomUUID(),revision:3,status:'closed'});
  assert.equal(closed.status,200);assert.equal((await rows()).length,3,'No mail for status-only events');
});
test('a failed outbox insert rolls back the ticket, history and write quota',async()=>{
  const author=await member();await member(true);
  await pool.query(`CREATE FUNCTION fixture_mail_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'private failure'; END $$;
    CREATE TRIGGER fixture_mail_fail BEFORE INSERT ON exp_member_ticket_mail FOR EACH ROW EXECUTE FUNCTION fixture_mail_fail()`);
  const id=randomUUID();
  try{await assert.rejects(action(author,{action:'create-ticket',id,subject:'X',message:'X'}));}
  finally{await pool.query('DROP TRIGGER fixture_mail_fail ON exp_member_ticket_mail; DROP FUNCTION fixture_mail_fail()');}
  for(const table of ['exp_member_ticket','exp_member_ticket_event','exp_member_ticket_limit'])assert.equal((await pool.query(`SELECT * FROM ${table}`)).rowCount,0);
});
test('pause prevents new queue entries and a paused worker makes no network requests',async()=>{
  const author=await member();await member(true);
  assert.equal((await action(author,{action:'create-ticket',id:randomUUID(),subject:'X',message:'X'},{mailEnabled:false})).status,200);
  assert.equal((await rows()).length,0);
  await open(author);
  assert.deepEqual(await worker({enabled:false,send:()=>assert.fail('Paused sender')}),{accepted:0,retry:0,failed:0,skipped:0});
  assert.equal((await rows())[0].attempts,0);
});
test('minimal mail goes to the authorized audience, without names, subject, message or bearer token',async()=>{
  const author=await member(),staff=await member(true),id=await open(author),sent=[];
  await reply(staff,id);
  assert.equal((await worker({send:async(mail,key)=>{sent.push({mail,key});return randomUUID();}})).accepted,2);
  assert.deepEqual(new Set(sent.map(s=>s.mail.to)),new Set([`${author}@example.test`,`${staff}@example.test`]));
  assert.ok(sent.some(s=>s.mail.text.includes(`/account/support?ticket=${id}`)));
  assert.ok(sent.some(s=>s.mail.text.includes(`/account/tickets?ticket=${id}`)));
  for(const sentMail of sent){assert.doesNotMatch(JSON.stringify(sentMail),/Secret|Private Name|token=|otp|user_id/);assert.match(sentMail.key,/^exp-ticket\/[a-f0-9-]+$/);}
  assert.ok((await rows()).every(r=>r.state==='accepted' && r.mail===null && r.provider_id));
  assert.equal((await worker({send:()=>assert.fail('Already accepted')})).accepted,0);
});
test('opt-out cancels queued alerts, stays separate from news and does not replay old events on opt-in',async()=>{
  const author=await member(),staff=await member(true);await open(author);
  assert.equal((await rows()).length,1);
  assert.equal((await action(staff,{action:'save-ticket-preferences',emailAlerts:false})).status,200);
  assert.equal((await rows()).length,0);await open(author);assert.equal((await rows()).length,0);
  assert.equal((await pool.query('SELECT * FROM exp_member_news')).rowCount,0);
  await action(staff,{action:'save-ticket-preferences',emailAlerts:true});assert.equal((await rows()).length,0);
  await open(author);assert.equal((await rows()).length,1);
});
test('grant revocation, loss of email verification, ticket deletion and account deletion suppress mail',async()=>{
  const author=await member(),staff=await member(true),id=await open(author);
  await pool.query('DELETE FROM exp_member_support_grant WHERE user_id=$1',[staff]);
  assert.equal((await worker({send:()=>assert.fail('Revoked staff')})).skipped,1);
  await reply(author,id);assert.equal((await rows()).length,1,'No new recipient after revocation');
  await pool.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES($1,'Fixture')",[staff]);
  await open(author);await pool.query('UPDATE exp_member_user SET "emailVerified"=false WHERE id=$1',[staff]);
  assert.equal((await worker({send:()=>assert.fail('Unverified recipient')})).skipped,1);
  await pool.query('UPDATE exp_member_user SET "emailVerified"=true WHERE id=$1',[staff]);
  const deleted=await open(author);await action(author,{action:'delete-ticket',id:deleted,confirmation:'DELETE'});
  assert.equal((await rows()).filter(r=>r.state==='pending').length,0);
  await open(author);await pool.query('DELETE FROM exp_member_user WHERE id=$1',[author]);
  assert.equal((await rows()).length,0,'Author erasure cascades all ticket jobs');
});
test('transient/ambiguous failure retries the exact frozen envelope and provider key',async()=>{
  const author=await member();await member(true);await open(author);
  const attempts=[],accepted=new Map();
  const send=async(mail,key)=>{attempts.push({mail,key});if(!accepted.has(key)){accepted.set(key,randomUUID());throw new Error('Provider accepted, response lost');}return accepted.get(key);};
  assert.equal((await worker({send})).retry,1);
  assert.equal((await worker({send})).retry,0,'Backoff respected');await due();
  assert.equal((await worker({send,origin:'https://changed.example.test',from:'Changed <changed@example.test>'})).accepted,1);
  assert.deepEqual(attempts[0],attempts[1]);assert.equal(accepted.size,1);
});
test('lost DB acknowledgement recovers after lease expiry without a second provider acceptance',async()=>{
  const author=await member();await member(true);await open(author);
  const accepted=new Map(),calls=[];
  const send=async(mail,key)=>{calls.push({mail,key});if(!accepted.has(key))accepted.set(key,randomUUID());return accepted.get(key);};
  const broken={connect:()=>pool.connect(),query:(sql,params)=>{
    if(sql.startsWith('UPDATE exp_member_ticket_mail SET state='))throw new Error('Acknowledgement lost');
    return pool.query(sql,params);
  }};
  await assert.rejects(worker({pool:broken,send}),/Acknowledgement lost/);
  assert.equal((await worker({send})).accepted,0,'Live lease prevents another send');
  await due();assert.equal((await worker({send})).accepted,1);
  assert.deepEqual(calls[0],calls[1]);assert.equal(accepted.size,1);
});
test('concurrent workers claim disjoint jobs and honor a bounded batch',async()=>{
  const author=await member();await member(true);for(let i=0;i<5;i++)await open(author);
  const keys=[];const send=async(mail,key)=>{keys.push(key);return randomUUID();};
  const results=await Promise.all([worker({send,limit:2}),worker({send,limit:2})]);
  assert.equal(results.reduce((n,r)=>n+r.accepted,0),4);assert.equal(new Set(keys).size,4);
  assert.equal((await worker({send})).accepted,1);assert.equal(new Set(keys).size,5);
});
test('old, exhausted or permanently rejected jobs stop without retrying beyond provider deduplication',async()=>{
  const author=await member();await member(true);await open(author);
  await pool.query("UPDATE exp_member_ticket_mail SET first_attempt_at=now()-interval '23 hours 1 minute',attempts=1");
  assert.equal((await worker({send:()=>assert.fail('Expired key')})).failed,1);
  await open(author);await pool.query("UPDATE exp_member_ticket_mail SET attempts=8 WHERE state='pending'");
  assert.equal((await worker({send:()=>assert.fail('Attempt cap')})).failed,1);
  await open(author);assert.equal((await worker({send:async()=>{const e=new Error('private provider detail');e.retryable=false;throw e;}})).failed,1);
  assert.ok((await rows()).every(r=>r.mail===null && r.state==='failed'));
});
test('changed recipient after an attempted send cancels rather than changing an idempotent envelope',async()=>{
  const author=await member(),staff=await member(true);await open(author);
  assert.equal((await worker({send:async()=>{throw new Error('Timeout');}})).retry,1);await due();
  await pool.query('UPDATE exp_member_user SET email=$2 WHERE id=$1',[staff,'changed@example.test']);
  assert.equal((await worker({send:()=>assert.fail('Changed recipient')})).skipped,1);
});
test('Resend adapter sends the idempotency header, validates receipts and classifies provider failures',async()=>{
  let status=200,body={id:randomUUID()};const seen=[];
  const server=http.createServer(async(req,res)=>{let raw='';for await(const chunk of req)raw+=chunk;seen.push({key:req.headers['idempotency-key'],body:JSON.parse(raw)});res.writeHead(status,{'content-type':'application/json'}).end(JSON.stringify(body));});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try{
    const send=createTicketMailer({apiKey:'fixture-only',fetcher:(url,options)=>{assert.equal(url,'https://api.resend.com/emails');return fetch(`http://127.0.0.1:${server.address().port}`,options);}});
    const mail={from:'support@example.test',to:'member@example.test',subject:'Service notice',text:'Sign in'};
    assert.equal(await send(mail,'fixture-key'),body.id);assert.deepEqual(seen[0],{key:'fixture-key',body:mail});
    status=429;await assert.rejects(send(mail,'fixture-key'),e=>e.retryable===true);
    status=422;await assert.rejects(send(mail,'fixture-key'),e=>e.retryable===false);
    status=200;body={};await assert.rejects(send(mail,'fixture-key'),/receipt unavailable/);
  }finally{await new Promise(resolve=>server.close(resolve));}
});

test('retention preview is read-only; apply requires the enabled exact policy',async()=>{
  const user=await member();await pool.query("INSERT INTO exp_member_beta_feedback(id,user_id,subject,message,created_at) VALUES(gen_random_uuid(),$1,'Old','Private',now()-interval '366 days')",[user]);
  const preview=await accountRetention({pool});assert.equal(preview.counts.betaFeedback,1);assert.equal(preview.mode,'preview');
  assert.equal((await pool.query('SELECT * FROM exp_member_beta_feedback')).rowCount,1);
  await assert.rejects(accountRetention({pool,apply:true,policy:accountRetentionVersion}));
  await assert.rejects(accountRetention({pool,apply:true,enabled:true,policy:'wrong'}));
  assert.equal((await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion})).counts.betaFeedback,1);
  assert.equal((await pool.query('SELECT * FROM exp_member_user')).rowCount,1,'Never expire an active account');
});
test('retention preserves open/recent tickets and pending reports, purging old closed threads with cascades',async()=>{
  const author=await member(),staff=await member(true),old=await open(author),recent=await open(author),stillOpen=await open(author);
  await reply(staff,old);
  await pool.query("UPDATE exp_member_ticket SET status='closed',updated_at=now()-interval '181 days' WHERE id=$1",[old]);
  await pool.query("UPDATE exp_member_ticket SET status='closed',updated_at=now()-interval '179 days' WHERE id=$1",[recent]);
  await pool.query("UPDATE exp_member_ticket SET updated_at=now()-interval '400 days' WHERE id=$1",[stillOpen]);
  await pool.query("INSERT INTO exp_member_community(user_id,handle,display_name,bio,link) VALUES($1,'fixture-user','Fixture','','')",[author]);
  for(const resolved of [null,'91 days','89 days'])await pool.query(`INSERT INTO exp_member_community_report(reporter_id,target_id,target_revision,category,reason,public_snapshot,created_at,resolved_at)
    VALUES($1,$2,gen_random_uuid(),'other','Private','{}',now()-interval '200 days',CASE WHEN $3::text IS NULL THEN NULL ELSE now()-$3::interval END)`,[staff,author,resolved]);
  const applied=await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion});
  assert.equal(applied.counts.closedTickets,1);assert.equal(applied.counts.resolvedReports,1);
  assert.deepEqual(new Set((await pool.query('SELECT id FROM exp_member_ticket')).rows.map(r=>r.id)),new Set([recent,stillOpen]));
  assert.equal((await pool.query('SELECT * FROM exp_member_ticket_event WHERE ticket_id=$1',[old])).rowCount,0);
  assert.equal((await pool.query('SELECT * FROM exp_member_support_audit WHERE ticket_id=$1',[old])).rowCount,0);
  assert.equal((await pool.query('SELECT * FROM exp_member_community_report WHERE resolved_at IS NULL')).rowCount,1);
});
test('cleanup respects batch bounds and skips a closed ticket being reopened concurrently',async()=>{
  const author=await member(),ids=[];for(let i=0;i<3;i++)ids.push(await open(author));
  await pool.query("UPDATE exp_member_ticket SET status='closed',updated_at=now()-interval '181 days'");
  const client=await pool.connect();
  try{
    await client.query('BEGIN');await client.query("UPDATE exp_member_ticket SET status='open',updated_at=now() WHERE id=$1",[ids[0]]);
    const applied=await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion,batchSize:1});
    assert.equal(applied.counts.closedTickets,1);await client.query('COMMIT');
  }finally{await client.query('ROLLBACK');client.release();}
  await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion});
  assert.deepEqual((await pool.query('SELECT id FROM exp_member_ticket')).rows,[{id:ids[0]}]);
});
test('expired auth data is cleaned without resetting live sessions, codes or hourly abuse limits',async()=>{
  const user=await member();
  for(const age of ['-1 hour','1 hour']) {
    await pool.query(`INSERT INTO exp_member_session(id,"userId",token,"expiresAt","updatedAt") VALUES(gen_random_uuid(),$1,$2,now()+$3::interval,now())`,[user,randomUUID(),age]);
    await pool.query(`INSERT INTO exp_member_verification(id,identifier,value,"expiresAt") VALUES(gen_random_uuid(),$1,'private hash',now()+$2::interval)`,[randomUUID(),age==='-1 hour'?'-2 days':age]);
    await pool.query(`INSERT INTO exp_member_mail_limit(key,sent_at,window_start,count) VALUES($1,now()+$2::interval,now()+$2::interval,5)`,[randomUUID(),age==='-1 hour'?'-2 days':age]);
    await pool.query(`INSERT INTO exp_member_rate_limit(id,key,count,"lastRequest") VALUES(gen_random_uuid(),$1,5,(extract(epoch FROM now()+$2::interval)*1000)::bigint)`,[randomUUID(),age==='-1 hour'?'-2 days':age]);
  }
  const applied=await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion});
  for(const key of ['sessions','challenges','mailLimits','authLimits'])assert.equal(applied.counts[key],1,key);
  assert.equal((await pool.query('SELECT count(*)::integer n FROM exp_member_session')).rows[0].n,1);
});
test('mail retention keeps recent receipts and active leases while removing only expired metadata',async()=>{
  const author=await member();await member(true);for(let i=0;i<4;i++)await open(author);
  const jobs=await rows();
  await pool.query("UPDATE exp_member_ticket_mail SET state='accepted',finished_at=now()-interval '31 days' WHERE id=$1",[jobs[0].id]);
  await pool.query("UPDATE exp_member_ticket_mail SET state='accepted',finished_at=now()-interval '29 days' WHERE id=$1",[jobs[1].id]);
  await pool.query("UPDATE exp_member_ticket_mail SET created_at=now()-interval '8 days' WHERE id=ANY($1::uuid[])",[[jobs[2].id,jobs[3].id]]);
  await pool.query("UPDATE exp_member_ticket_mail SET lease_until=now()+interval '1 minute' WHERE id=$1",[jobs[3].id]);
  assert.equal((await accountRetention({pool,apply:true,enabled:true,policy:accountRetentionVersion})).counts.mailReceipts,2);
  assert.deepEqual(new Set((await rows()).map(r=>r.id)),new Set([jobs[1].id,jobs[3].id]));
});

test('reviewed app and worker grants support real jobs without access to staff promotion, auth tokens or message text',async()=>{
  const author=await member(),staff=await member(true);
  await pool.query('CREATE ROLE exp_account_app; CREATE ROLE exp_account_jobs');
  const app=new pg.Pool({connectionString:url.href,options:'-c role=exp_account_app'});
  const jobs=new pg.Pool({connectionString:url.href,options:'-c role=exp_account_jobs'});
  try{
    await pool.query(`GRANT USAGE ON SCHEMA public TO exp_account_app;
      GRANT SELECT,INSERT,UPDATE,DELETE ON exp_member_user,exp_member_ticket,exp_member_ticket_event,exp_member_ticket_limit TO exp_account_app;
      GRANT SELECT ON exp_member_support_grant TO exp_account_app;
      GRANT SELECT,INSERT ON exp_member_support_audit TO exp_account_app`);
    await pool.query(await readFile(new URL('../migrations/grants/009_account_jobs.sql',import.meta.url),'utf8'));
    const id=await open(author);
    const body={action:'reply-ticket',id,receipt:randomUUID(),revision:1,message:'Private support answer'};
    assert.equal((await action(staff,body,{pool:app})).status,200);
    assert.equal((await action(author,{action:'tickets'},{pool:app})).body.ticketEmailsEnabled,true);
    assert.equal((await worker({pool:jobs})).accepted,2);
    await pool.query("UPDATE exp_member_ticket SET status='closed',updated_at=now()-interval '181 days' WHERE id=$1",[id]);
    assert.equal((await accountRetention({pool:jobs})).counts.closedTickets,1);
    assert.equal((await accountRetention({pool:jobs,apply:true,enabled:true,policy:accountRetentionVersion})).counts.closedTickets,1);
    await assert.rejects(jobs.query('SELECT token FROM exp_member_session'),/permission denied/);
    await assert.rejects(jobs.query('SELECT message FROM exp_member_ticket_event'),/permission denied/);
    await assert.rejects(jobs.query('SELECT message FROM exp_member_beta_feedback'),/permission denied/);
    await assert.rejects(jobs.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES(gen_random_uuid(),'Promote')"),/permission denied/);
    await assert.rejects(jobs.query('UPDATE exp_member_user SET "emailVerified"=true'),/permission denied/);
    await assert.rejects(jobs.query('UPDATE exp_member_community_report SET resolved_at=now()'),/permission denied/);
  }finally{
    await app.end();await jobs.end();await pool.query('DROP OWNED BY exp_account_app,exp_account_jobs; DROP ROLE exp_account_app,exp_account_jobs');
  }
});

test('operator CLI previews aggregate counts, refuses paused mutations and redacts configuration failures',async()=>{
  const user=await member();
  await pool.query("INSERT INTO exp_member_beta_feedback(id,user_id,subject,message,created_at) VALUES(gen_random_uuid(),$1,'Private','Private',now()-interval '366 days')",[user]);
  const run=args=>promisify(execFile)(process.execPath,['scripts/run_account_jobs.mjs',...args],{
    env:{...process.env,EXP_ACCOUNT_JOBS_DATABASE_URL:url.href,ACCOUNT_RETENTION_ENABLED:'false',ACCOUNT_TICKET_MAIL_ENABLED:'false'}
  });
  const preview=await run(['--preview']);assert.equal(JSON.parse(preview.stdout).retention.counts.betaFeedback,1);
  assert.doesNotMatch(preview.stdout,/Private|example.test|postgresql|password|token/);
  for(const args of [['--mail'],[`--purge=${accountRetentionVersion}`],['--purge=wrong']])await assert.rejects(run(args),e=>{
    assert.equal(e.code,1);assert.doesNotMatch(e.stderr,/example.test|postgresql|password|token/);return true;
  });
  assert.equal((await pool.query('SELECT * FROM exp_member_beta_feedback')).rowCount,1);
});

test('migration 009 preserves existing accounts and private threads without backfilling email jobs',async()=>{
  await operator.query('CREATE DATABASE exp_account_upgrade_test');
  const upgradeURL=new URL(db);upgradeURL.pathname='/exp_account_upgrade_test';
  const upgrade=new pg.Pool({connectionString:upgradeURL.href});
  try{
    for(const file of ['003_free_accounts.sql','005_member_beta.sql','007_community_profiles.sql','008_news_and_tickets.sql'])await upgrade.query(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));
    const id=randomUUID(),ticket=randomUUID();
    await upgrade.query(`INSERT INTO exp_member_user(id,name,email,"emailVerified","profileVisibility") VALUES($1,'Existing member','upgrade@example.test',true,'private')`,[id]);
    await upgrade.query("INSERT INTO exp_member_ticket(id,user_id,subject) VALUES($1,$2,'Existing private subject')",[ticket,id]);
    await upgrade.query("INSERT INTO exp_member_ticket_event(id,ticket_id,actor_id,actor_kind,kind,message,sequence) VALUES($1,$1,$2,'author','opened','Existing private text',1)",[ticket,id]);
    const legacy=await handleTickets({pool:upgrade,userId:id,enabled:false,body:{action:'tickets'}});
    assert.equal(legacy.status,200);assert.equal(legacy.body.ticketEmailPreferencesAvailable,false);assert.equal(legacy.body.tickets[0].id,ticket);
    assert.equal((await handleTickets({pool:upgrade,userId:id,body:{action:'ticket',id:ticket},enabled:false})).status,200);
    assert.equal((await handleTickets({pool:upgrade,userId:id,body:{action:'save-ticket-preferences',emailAlerts:false},enabled:false})).status,503);
    await upgrade.query(await readFile(new URL('../migrations/009_ticket_mail_and_retention.sql',import.meta.url),'utf8'));
    assert.equal((await handleTickets({pool:upgrade,userId:id,enabled:false,body:{action:'tickets'}})).body.ticketEmailPreferencesAvailable,true);
    assert.equal((await upgrade.query('SELECT email FROM exp_member_user WHERE id=$1',[id])).rows[0].email,'upgrade@example.test');
    assert.equal((await upgrade.query('SELECT message FROM exp_member_ticket_event WHERE ticket_id=$1',[ticket])).rows[0].message,'Existing private text');
    assert.equal((await upgrade.query('SELECT * FROM exp_member_ticket_mail')).rowCount,0);
  }finally{await upgrade.end();await operator.query('DROP DATABASE exp_account_upgrade_test');}
});

const jobToken=randomUUID()+randomUUID();
async function jobServer(env,run,extra={}) {
  const handler=createAccountJobHandler({pool,env:{EXP_ACCOUNT_JOB_TOKEN:jobToken,...env},send:async()=>randomUUID(),...extra});
  const server=http.createServer(handler);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin=`http://127.0.0.1:${server.address().port}`;
  const request=(body={operation:'preview'},options={})=>fetch(`${origin}/api/account-jobs`,{method:'POST',headers:{authorization:`Bearer ${jobToken}`,'content-type':'application/json',...options.headers},body:JSON.stringify(body),...options});
  try{await run({request,origin});}finally{await new Promise(resolve=>server.close(resolve));}
}
test('job HTTP boundary requires its dedicated token and validates requests before storage',async()=>{
  await jobServer({},async({request,origin})=>{
    for(const authorization of ['',`Bearer ${jobToken}wrong`])assert.equal((await request(undefined,{headers:{authorization,'content-type':'application/json'}})).status,401);
    assert.equal((await fetch(`${origin}/api/account-jobs`,{headers:{authorization:`Bearer ${jobToken}`}})).status,405);
    assert.equal((await request({operation:'sql'})).status,400);
    assert.equal((await request({operation:'preview',userId:randomUUID()})).status,400);
    assert.equal((await request({operation:'preview',text:'x'.repeat(2100)})).status,413);
    assert.equal((await request({operation:'mail'})).status,503);
    assert.equal((await request({operation:'retention'})).status,503);
  },{pool:{query:()=>assert.fail('Denied/paused jobs must not access storage')}});
});
test('HTTP preview is read-only and the GitHub client prints only allowed aggregate fields',async()=>{
  const user=await member();await pool.query("INSERT INTO exp_member_beta_feedback(id,user_id,subject,message,created_at) VALUES(gen_random_uuid(),$1,'Private subject','Private message',now()-interval '366 days')",[user]);
  await jobServer({},async({request,origin})=>{
    const response=await request();assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
    const body=await response.json();assert.equal(body.retention.mode,'preview');assert.equal(body.retention.counts.betaFeedback,1);
    const {stdout}=await promisify(execFile)(process.execPath,['scripts/run_hosted_account_job.mjs','preview'],{env:{...process.env,NODE_ENV:'test',EXP_ACCOUNT_JOB_TOKEN:jobToken,EXP_ACCOUNT_JOB_URL:`${origin}/api/account-jobs`}});
    assert.equal(JSON.parse(stdout).counts.betaFeedback,1);assert.doesNotMatch(stdout,/Private|example.test|token|postgresql|provider_id/);
    assert.equal((await pool.query('SELECT * FROM exp_member_beta_feedback')).rowCount,1);
  });
});
test('HTTP mail and deletion are independent gates; approved policy only deletes eligible rows',async()=>{
  const author=await member();await member(true);const closed=await open(author),stillOpen=await open(author);
  await pool.query("UPDATE exp_member_ticket SET status='closed',updated_at=now()-interval '181 days' WHERE id=$1",[closed]);
  await jobServer({ACCOUNT_TICKET_MAIL_ENABLED:'true',RESEND_API_KEY:'fixture-only',SIGNUP_FROM_EMAIL:'fixture@example.test',ACCOUNT_PUBLIC_ORIGIN:'https://accounts.example.test'},async({request})=>{
    const response=await request({operation:'mail'});assert.equal(response.status,200);
    const body=await response.json();assert.equal(body.ticketMail.accepted,2);assert.doesNotMatch(JSON.stringify(body),/example.test|Secret|recipient|provider_id/);
    assert.equal((await request({operation:'retention'})).status,503);
  });
  await jobServer({ACCOUNT_RETENTION_ENABLED:'true',ACCOUNT_RETENTION_POLICY:'wrong'},async({request})=>{assert.equal((await request({operation:'retention'})).status,503);});
  await jobServer({ACCOUNT_RETENTION_ENABLED:'true',ACCOUNT_RETENTION_POLICY:accountRetentionVersion},async({request})=>{
    const response=await request({operation:'retention'});assert.equal(response.status,200);assert.equal((await response.json()).retention.counts.closedTickets,1);
    assert.deepEqual((await pool.query('SELECT id FROM exp_member_ticket')).rows,[{id:stillOpen}]);
    assert.equal((await request({operation:'mail'})).status,503);
  });
});
test('job HTTP errors stay generic and the client refuses redirects or unrelated destinations',async()=>{
  await jobServer({},async({request})=>{
    const response=await request();assert.equal(response.status,503);assert.doesNotMatch(await response.text(),/private trace|password|postgres/);
  },{pool:{query:async()=>{throw new Error('private trace with password');}}});
  const server=http.createServer((req,res)=>res.writeHead(302,{location:'https://example.test/stolen'}).end());
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const run=url=>promisify(execFile)(process.execPath,['scripts/run_hosted_account_job.mjs','preview'],{env:{...process.env,NODE_ENV:'test',EXP_ACCOUNT_JOB_TOKEN:jobToken,EXP_ACCOUNT_JOB_URL:url}});
  try{
    for(const target of [`http://127.0.0.1:${server.address().port}/api/account-jobs`,'https://example.test/api/account-jobs'])await assert.rejects(run(target),error=>{
      assert.equal(error.code,1);assert.doesNotMatch(error.stderr,new RegExp(jobToken));assert.doesNotMatch(error.stderr,/example.test|private trace/);return true;
    });
  }finally{await new Promise(resolve=>server.close(resolve));}
});
test('production job wrapper refuses missing tokens and unverified TLS without connecting',async()=>{
  const priorToken=process.env.EXP_ACCOUNT_JOB_TOKEN,priorDB=process.env.EXP_ACCOUNT_JOBS_DATABASE_URL;
  process.env.EXP_ACCOUNT_JOB_TOKEN=jobToken;process.env.EXP_ACCOUNT_JOBS_DATABASE_URL='postgresql://fixture:fixture@invalid.example.test/exp_accounts?sslmode=disable';
  const server=http.createServer(accountJobsEndpoint);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try{
    const url=`http://127.0.0.1:${server.address().port}/api/account-jobs`;
    assert.equal((await fetch(url)).status,401);
    assert.equal((await fetch(url,{headers:{authorization:`Bearer ${jobToken}`}})).status,503);
  }finally{
    await new Promise(resolve=>server.close(resolve));
    if(priorToken===undefined)delete process.env.EXP_ACCOUNT_JOB_TOKEN;else process.env.EXP_ACCOUNT_JOB_TOKEN=priorToken;
    if(priorDB===undefined)delete process.env.EXP_ACCOUNT_JOBS_DATABASE_URL;else process.env.EXP_ACCOUNT_JOBS_DATABASE_URL=priorDB;
  }
});
