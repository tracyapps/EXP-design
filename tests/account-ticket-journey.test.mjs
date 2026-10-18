// Full local HTTP journey: real auth/DB/worker, with provider traffic captured
// on loopback. This never loads hosted credentials or delivers real email.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomBytes,randomUUID} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import http from 'node:http';
import pg from 'pg';
import {createAccountService,accountConsentVersion} from '../server/accounts/service.js';
import {createAccountNodeHandler} from '../server/accounts/runtime.js';
import {createAccountJobHandler} from '../server/accounts/jobs.js';
import {createTicketMailer} from '../server/accounts/ticket-mail.js';

const db=process.env.EXP_ACCOUNT_TEST_DATABASE_URL;
if(!db || !new URL(db).searchParams.get('host')?.startsWith('/tmp/exp-account-test.') || process.env.NODE_ENV==='production')
  throw new Error('Disposable local PostgreSQL required');

test('signed-in ticket journey reaches the HTTP worker and captured provider through separate restricted roles',async()=>{
  const operator=new pg.Pool({connectionString:db});
  const suffix=randomBytes(6).toString('hex'),database=`exp_journey_${suffix}`;
  const appRole=`exp_journey_app_${suffix}`,jobRole=`exp_journey_jobs_${suffix}`;
  const url=new URL(db);url.pathname=`/${database}`;
  let pool,app,jobs,server;
  let databaseCreated=false,rolesCreated=false;
  try{
    await operator.query(`CREATE DATABASE ${database}`);databaseCreated=true;
    pool=new pg.Pool({connectionString:url.href});
    for(const file of ['003_free_accounts.sql','005_member_beta.sql','007_community_profiles.sql','008_news_and_tickets.sql','009_ticket_mail_and_retention.sql'])
      await pool.query(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));
    await pool.query(`CREATE ROLE ${appRole}; CREATE ROLE ${jobRole}`);rolesCreated=true;
    await pool.query(`GRANT USAGE ON SCHEMA public TO ${appRole};
      GRANT SELECT,INSERT,UPDATE,DELETE ON exp_member_user,exp_member_session,exp_member_identity,
        exp_member_verification,exp_member_rate_limit,exp_member_mail_limit,
        exp_member_ticket,exp_member_ticket_event,exp_member_ticket_limit TO ${appRole};
      GRANT SELECT ON exp_member_support_grant TO ${appRole};
      GRANT SELECT,INSERT ON exp_member_support_audit TO ${appRole}`);
    const grants=await readFile(new URL('../migrations/grants/009_account_jobs.sql',import.meta.url),'utf8');
    await pool.query(grants.replaceAll('exp_account_app',appRole).replaceAll('exp_account_jobs',jobRole));
    app=new pg.Pool({connectionString:url.href,options:`-c role=${appRole}`});
    jobs=new pg.Pool({connectionString:url.href,options:`-c role=${jobRole}`});
    assert.equal((await app.query('SELECT current_user')).rows[0].current_user,appRole);
    assert.equal((await jobs.query('SELECT current_user')).rows[0].current_user,jobRole);

    const codes=new Map(),captured=[],token=randomBytes(32).toString('hex');
    let accountHandler,jobHandler;
    server=http.createServer(async(req,res)=>{
      if(req.url==='/api/account')return accountHandler(req,res);
      if(req.url==='/api/account-jobs')return jobHandler(req,res);
      if(req.url==='/fixture-provider'){
        let raw='';for await(const chunk of req)raw+=chunk;
        captured.push({mail:JSON.parse(raw),key:req.headers['idempotency-key']});
        return res.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify({id:randomUUID()}));
      }
      res.writeHead(404).end();
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const origin=`http://127.0.0.1:${server.address().port}`;
    const service=createAccountService({pool:app,origin,secret:randomBytes(32).toString('hex'),ticketsEnabled:true,ticketMailEnabled:true,
      sendOTP:async({email,otp})=>{codes.set(email,otp);}});
    accountHandler=createAccountNodeHandler({handle:service.handle,origin,env:{}});
    const send=createTicketMailer({apiKey:'local-fixture-only',fetcher:(target,options)=>{
      assert.equal(target,'https://api.resend.com/emails');
      return fetch(`${origin}/fixture-provider`,options);
    }});
    jobHandler=createAccountJobHandler({pool:jobs,env:{EXP_ACCOUNT_JOB_TOKEN:token,ACCOUNT_TICKET_MAIL_ENABLED:'true',
      RESEND_API_KEY:'local-fixture-only',SIGNUP_FROM_EMAIL:'EXP <support@example.test>',ACCOUNT_PUBLIC_ORIGIN:origin},send});
    async function account(body,cookie=''){
      const r=await fetch(`${origin}/api/account`,{method:'POST',headers:{origin,cookie,'content-type':'application/json'},body:JSON.stringify(body)});
      return {status:r.status,body:await r.json(),cookie:r.headers.getSetCookie().map(c=>c.split(';')[0]).join('; ')};
    }
    async function register(email){
      assert.equal((await account({action:'send-code',email})).status,200);
      assert.match(codes.get(email),/^\d{6}$/);
      const r=await account({action:'verify-code',email,otp:codes.get(email),intent:'register',name:'Private fixture identity',
        accountConsent:true,consentVersion:accountConsentVersion});
      assert.equal(r.status,200);assert.ok(r.cookie);return r.cookie;
    }
    async function run(operation){
      const {stdout,stderr}=await promisify(execFile)(process.execPath,['scripts/run_hosted_account_job.mjs',operation],{
        env:{...process.env,NODE_ENV:'test',EXP_ACCOUNT_JOB_TOKEN:token,EXP_ACCOUNT_JOB_URL:`${origin}/api/account-jobs`}});
      assert.equal(stderr,'');assert.doesNotMatch(stdout,/example\.test|Private|fixture identity|Bearer|postgres|provider_id/);
      return JSON.parse(stdout);
    }
    const author=await register('journey-author@example.test'),staff=await register('journey-support@example.test'),other=await register('journey-other@example.test');
    const staffId=(await account({action:'session'},staff)).body.user.id;
    await pool.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES($1,'Local journey fixture')",[staffId]);
    const denied=await fetch(`${origin}/api/account-jobs`,{method:'POST',headers:{cookie:staff,'content-type':'application/json'},body:'{"operation":"preview"}'});
    assert.equal(denied.status,401,'A support session is not job authorization');

    const id=randomUUID();
    assert.equal((await account({action:'create-ticket',id,subject:'Private fixture subject',message:'Private fixture message'},author)).status,200);
    assert.equal((await account({action:'ticket',id},other)).status,404);
    assert.equal((await account({action:'ticket',id},staff)).status,200);
    const preview=await run('preview');assert.equal(preview.operation,'preview');assert.equal(captured.length,0);
    assert.equal((await pool.query("SELECT count(*)::integer n FROM exp_member_ticket_mail WHERE state='pending'")).rows[0].n,1);
    assert.equal((await run('mail')).counts.accepted,1);
    assert.equal(captured[0].mail.to,'journey-support@example.test');
    assert.ok(captured[0].mail.text.includes(`${origin}/account/support?ticket=${id}`));
    assert.equal((await run('mail')).counts.accepted,0,'No duplicate after provider acceptance');

    const reply=(cookie,revision)=>account({action:'reply-ticket',id,revision,receipt:randomUUID(),message:'Private fixture reply'},cookie);
    assert.equal((await reply(staff,1)).status,200);
    assert.equal((await account({action:'save-ticket-preferences',emailAlerts:false},author)).status,200);
    assert.equal((await run('mail')).counts.accepted,0,'Opt-out cancels the queued reply notice');
    assert.equal((await account({action:'save-ticket-preferences',emailAlerts:true},author)).status,200);
    assert.equal((await run('mail')).counts.accepted,0,'Opt-in does not replay cancelled mail');
    assert.equal((await reply(staff,2)).status,200);
    assert.equal((await run('mail')).counts.accepted,1);
    assert.equal(captured[1].mail.to,'journey-author@example.test');
    assert.ok(captured[1].mail.text.includes(`${origin}/account/tickets?ticket=${id}`));
    for(const mail of captured){
      assert.doesNotMatch(JSON.stringify(mail),/Private fixture|token=|otp=|Bearer/);
      assert.match(mail.key,/^exp-ticket\/[a-f0-9-]+$/);
    }
    assert.equal(new Set(captured.map(m=>m.key)).size,2);

    assert.equal((await reply(author,3)).status,200);
    await pool.query('DELETE FROM exp_member_support_grant WHERE user_id=$1',[staffId]);
    assert.equal((await run('mail')).counts.skipped,1,'Revoked staff receive no pending alert');
    assert.equal((await account({action:'ticket',id},staff)).status,404);
    assert.equal(captured.length,2);
    assert.equal((await account({action:'set-ticket-status',id,receipt:randomUUID(),revision:4,status:'closed'},author)).status,200);
    assert.equal((await account({action:'delete-ticket',id,confirmation:'DELETE'},author)).status,200);
    assert.equal((await pool.query('SELECT count(*)::integer n FROM exp_member_ticket_mail')).rows[0].n,0);
    assert.equal((await account({action:'sign-out'},author)).status,200);
    assert.equal((await account({action:'tickets'},author)).status,401);
    await assert.rejects(jobs.query('SELECT token FROM exp_member_session'),/permission denied/);
    await assert.rejects(jobs.query('SELECT message FROM exp_member_ticket_event'),/permission denied/);
    await assert.rejects(app.query("INSERT INTO exp_member_support_grant(user_id,operator_reference) VALUES($1,'Forbidden')",[staffId]),/permission denied/);
  }finally{
    if(server)await new Promise(resolve=>server.close(resolve));
    if(app)await app.end();if(jobs)await jobs.end();
    if(rolesCreated){await pool.query(`DROP OWNED BY ${appRole},${jobRole}; DROP ROLE ${appRole},${jobRole}`);}
    if(pool)await pool.end();
    if(databaseCreated)await operator.query(`DROP DATABASE ${database}`);
    await operator.end();
  }
});
