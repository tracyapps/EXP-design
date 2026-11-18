import test,{before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import pg from 'pg';
import {createTeamStore} from '../server/teams/store.js';
import {createTeamHandler} from '../server/teams/handlers.js';
import {hashToken} from '../server/interest/store.js';
const connectionString=process.env.EXP_TEAM_TEST_DATABASE_URL;
if(!connectionString || !new URL(connectionString).searchParams.get('host')?.startsWith('/tmp/exp-team-test.'))throw new Error('Use scripts/verify_team_research.sh');
let pool,store,handler,mails;
const env={EXP_INTEREST_DATABASE_URL:'isolated-test',INTEREST_PUBLIC_ORIGIN:'https://example.test',TEAM_RESEARCH_ENABLED:'true',TEAM_RESEARCH_POLICY:'team-research-90d-v1',RESEND_API_KEY:'test',SIGNUP_FROM_EMAIL:'EXP <test@example.test>'};
const token=()=>randomBytes(32).toString('base64url');
const answers={role:'designer',problem:'our library and code disagree',systems:['Mac'],tools:['design tokens']};
const contact=(key,email='person@example.test')=>({operation:'contact',token:key,email,consent:true,consentVersion:'team-research-contact-v1'});
async function call(body,{method='POST',origin='https://example.test',service=handler,type='application/json'}={}){
  let output;const headers={};const response={statusCode:200,setHeader:(k,v)=>headers[k]=v,end:value=>output=JSON.parse(value)};
  await service({method,body,headers:{origin,'content-type':type}},response);
  return {status:response.statusCode,body:output,headers};
}
const row=async()=> (await pool.query('SELECT * FROM exp_team_research')).rows[0];
const save=async(key=token())=>{assert.equal((await call({operation:'save',token:key,answers})).status,201);return key;};
before(async()=>{pool=new pg.Pool({connectionString,max:8});await pool.query(await readFile(new URL('../migrations/013_team_research.sql',import.meta.url),'utf8'));await pool.query(await readFile(new URL('../migrations/014_team_research_inbox.sql',import.meta.url),'utf8'));store=createTeamStore(pool);});
after(async()=>pool.end());
beforeEach(async()=>{await pool.query('TRUNCATE exp_team_research, exp_team_research_limit');mails=[];handler=createTeamHandler({env,storeFactory:()=>store,mailer:async(config,email,links)=>mails.push({email,...links})});});
test('account-free response persists with no email, only a hashed capability',async()=>{
 const key=await save();const saved=await row();assert.equal(saved.email,null);assert.equal(saved.capability_hash,hashToken(key));assert.equal(saved.answers.problem,answers.problem);assert.equal(mails.length,0);assert.equal(saved.survey_version,'team-research-v1');assert.ok(saved.expires_at>saved.created_at);
});
test('concurrent retries save one response and cannot replace it',async()=>{
 const key=token();const results=await Promise.all(Array.from({length:8},()=>call({operation:'save',token:key,answers})));
 assert.ok(results.every(x=>x.status===201));assert.equal((await pool.query('SELECT count(*)::int AS n FROM exp_team_research')).rows[0].n,1);
 assert.equal((await call({operation:'save',token:key,answers:{problem:'changed'}})).body.state,'already_saved');assert.equal((await row()).answers.problem,answers.problem);
});
test('empty, oversized, invalid and unknown fields are rejected without storage',async()=>{
 for(const bad of [{},{role:'invented'},{problem:'a'.repeat(1501)},{email:'oops@example.test'},{systems:['Mac','not sure']},{tools:['design tokens','design tokens']}])assert.equal((await call({operation:'save',token:token(),answers:bad})).status,400);
 assert.equal((await call('x'.repeat(12001))).status,413);assert.equal(await row(),undefined);
});
test('origin, JSON and method boundaries reject writes',async()=>{
 const data={operation:'save',token:token(),answers};assert.equal((await call(data,{origin:'https://elsewhere.test'})).status,403);assert.equal((await call(data,{type:'text/plain'})).status,415);assert.equal((await call(data,{method:'PUT'})).status,405);assert.equal(await row(),undefined);
 const status=await call(null,{method:'GET'});assert.equal(status.body.collecting,true);assert.equal(status.body.contact,true);assert.equal(status.headers['cache-control'],'no-store');
});
test('contact requires explicit, versioned permission; never edits survey answers',async()=>{
 const key=await save();for(const fields of [{consent:false},{consentVersion:'pro-interest-v1'},{email:'bad'}])assert.equal((await call({...contact(key),...fields})).status,400);
 assert.equal(mails.length,0);assert.equal((await row()).email,null);
 assert.equal((await call(contact(key))).status,202);assert.equal((await row()).confirmed_at,null);assert.equal((await row()).consent_version,'team-research-contact-v1');assert.equal((await row()).answers.problem,answers.problem);
});
test('concurrent contact sends one confirmation, with fragment links and no raw token storage',async()=>{
 const key=await save();await Promise.all(Array.from({length:3},()=>call(contact(key))));assert.equal(mails.length,1);assert.equal(new URL(mails[0].confirm).search,'');assert.equal(new URL(mails[0].manage).hash.slice(1),key);assert.ok(!JSON.stringify(await row()).includes(new URL(mails[0].confirm).hash.slice(1)));
});
test('GET cannot confirm; exactly one concurrent POST consumes confirmation',async()=>{
 const key=await save();await call(contact(key));const confirmation=new URL(mails[0].confirm).hash.slice(1);
 await call({operation:'confirm',token:confirmation},{method:'GET'});assert.equal((await row()).confirmed_at,null);
 const results=await Promise.all(Array.from({length:5},()=>call({operation:'confirm',token:confirmation})));
 assert.equal(results.filter(r=>r.status===200).length,1);assert.equal((await row()).confirmation_hash,null);assert.ok((await row()).confirmed_at);
});
test('expired and tampered confirmation cannot enroll',async()=>{
 const key=await save();await call(contact(key));await pool.query("UPDATE exp_team_research SET confirmation_expires_at=now()-interval '1 second'");
 assert.equal((await call({operation:'confirm',token:new URL(mails[0].confirm).hash.slice(1)})).status,400);assert.equal((await call({operation:'confirm',token:token()})).status,400);assert.equal((await row()).confirmed_at,null);
});
test('failed mail retains answers and allows a retry without contact permission',async()=>{
 const key=await save();const failing=createTeamHandler({env,storeFactory:()=>store,mailer:async()=>{throw new Error('failure');}});
 assert.equal((await call(contact(key),{service:failing})).status,502);assert.equal((await row()).email,null);assert.equal((await row()).confirmation_hash,null);assert.equal((await row()).answers.problem,answers.problem);
 assert.equal((await call(contact(key))).status,202);assert.equal(mails.length,1);
});
test('withdrawal clears email and cancels confirmation; answers remain',async()=>{
 const key=await save();await call(contact(key));const confirmation=new URL(mails[0].confirm).hash.slice(1);
 await call({operation:'withdraw',token:key});assert.equal((await row()).email,null);assert.equal((await row()).consent_version,null);assert.ok((await row()).answers.problem);
 assert.equal((await call({operation:'confirm',token:confirmation})).status,400);
});
test('confirmation cannot re-enroll a withdrawn response',async()=>{
 const key=await save();await call(contact(key));const confirmation=new URL(mails[0].confirm).hash.slice(1);await call({operation:'confirm',token:confirmation});await call({operation:'withdraw',token:key});assert.equal((await call({operation:'confirm',token:confirmation})).status,400);assert.equal((await row()).confirmed_at,null);
});
test('a wrong capability cannot delete another response; delete is repeatable',async()=>{
 const key=await save();await call(contact(key));await call({operation:'erase',token:token()});assert.ok(await row());
 assert.equal((await call({operation:'erase',token:key})).status,200);assert.equal(await row(),undefined);assert.equal((await call({operation:'erase',token:key})).status,200);
});
test('paused enrollment still permits withdrawal and deletion without mail configuration',async()=>{
 const key=await save();await call(contact(key));const paused=createTeamHandler({env:{...env,TEAM_RESEARCH_ENABLED:'false',RESEND_API_KEY:''},storeFactory:()=>store});
 assert.equal((await call({operation:'save',token:token(),answers},{service:paused})).status,503);
 assert.equal((await call({operation:'withdraw',token:key},{service:paused})).status,200);assert.equal((await row()).email,null);
 assert.equal((await call({operation:'erase',token:key},{service:paused})).status,200);assert.equal(await row(),undefined);
});
test('expired responses cannot be contacted, confirmed, or treated as a fresh successful retry',async()=>{
 const key=await save();await call(contact(key));await pool.query("UPDATE exp_team_research SET expires_at=now()-interval '1 second'");
 assert.equal((await call({operation:'save',token:key,answers})).status,410);
 assert.equal((await call({operation:'confirm',token:new URL(mails[0].confirm).hash.slice(1)})).status,400);
 await call(contact(key,'new@example.test'));assert.equal(mails.length,1);
});
test('shared storage budgets hold across concurrent workers',async()=>{
 const results=await Promise.all(Array.from({length:12},()=>store.budget('test',3,3600)));assert.equal(results.filter(Boolean).length,3);
});

test('owner list redacts unconfirmed emails and all capability fields; withdrawal/deletion are reflected',async()=>{
  const key=await save();await call(contact(key));
  let result=await store.listResponses();assert.equal(result.responses[0].followupEmail,null);assert.equal(result.responses[0].contactState,'pending');
  assert.ok(!JSON.stringify(result).includes('capability_hash'));assert.ok(!JSON.stringify(result).includes('confirmation_hash'));
  await call({operation:'confirm',token:new URL(mails[0].confirm).hash.slice(1)});
  result=await store.listResponses();assert.equal(result.responses[0].followupEmail,'person@example.test');
  await call({operation:'withdraw',token:key});result=await store.listResponses();assert.equal(result.responses[0].followupEmail,null);
  await call({operation:'erase',token:key});assert.equal((await store.listResponses()).responses.length,0);
});
test('inbox pagination uses public ids, excludes expired records and does not repeat rows',async()=>{
  for(let i=0;i<27;i++)await save();
  const first=await store.listResponses();assert.equal(first.responses.length,25);assert.ok(first.nextBefore);
  const last=await store.listResponses(first.nextBefore);assert.equal(last.responses.length,2);assert.equal(last.nextBefore,null);
  assert.equal(new Set([...first.responses,...last.responses].map(r=>r.id)).size,27);
  await pool.query("UPDATE exp_team_research SET expires_at=now()-interval '1 second'");assert.equal((await store.listResponses()).responses.length,0);
});
test('notification leases prevent concurrent claims, survive retries, and clear on deletion',async()=>{
  const key=await save();const claims=await Promise.all(Array.from({length:8},()=>store.claimOwnerNotification(key)));
  assert.equal(claims.filter(Boolean).length,1);const claim=claims.find(Boolean);
  await store.finishOwnerNotification(claim.claim,false);assert.equal(await store.claimOwnerNotification(key),null);
  await pool.query("UPDATE exp_team_research SET owner_notify_after=now()-interval '1 second'");
  const retry=await store.claimOwnerNotification(key);assert.ok(retry);await store.finishOwnerNotification(claim.claim,true);
  assert.equal((await row()).owner_notified_at,null); // stale worker cannot settle the newer lease
  await store.finishOwnerNotification(retry.claim,true);assert.equal(await store.claimOwnerNotification(key),null);
  await store.erase(key);assert.equal(await store.claimOwnerNotification(key),null);
});
test('cleanup removes expired answers, clears expired pending contact, and preserves confirmed current permission',async()=>{
  await save();await pool.query("UPDATE exp_team_research SET expires_at=now()-interval '1 second'");
  const key=await save();await call(contact(key));await pool.query("UPDATE exp_team_research SET confirmation_expires_at=now()-interval '1 second' WHERE email IS NOT NULL");
  const result=await store.cleanup();assert.equal(result.deleted,1);assert.equal(result.cleared,1);assert.equal((await row()).email,null);
});
