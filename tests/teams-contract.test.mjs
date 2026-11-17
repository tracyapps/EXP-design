// Fast contract checks; these do NOT substitute for the PostgreSQL suite.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createTeamHandler} from '../server/teams/handlers.js';
import {validateAnswers} from '../server/teams/schema.js';
const key='a'.repeat(43);
const env={TEAM_RESEARCH_ENABLED:'true',TEAM_RESEARCH_POLICY:'team-research-90d-v1',EXP_INTEREST_DATABASE_URL:'not-connected',INTEREST_PUBLIC_ORIGIN:'https://example.test',RESEND_API_KEY:'test',SIGNUP_FROM_EMAIL:'test@example.test'};
async function request(body,{config=env,store={},mailer=async()=>{},method='POST',origin='https://example.test',type='application/json'}={}){
 let result;let accessed=false;const headers={};const res={statusCode:200,setHeader:(k,v)=>headers[k]=v,end:text=>result=JSON.parse(text)};
 const handler=createTeamHandler({env:config,storeFactory:()=>{accessed=true;return store;},mailer});
 await handler({method,headers:{origin,'content-type':type},body},res);return {status:res.statusCode,result,headers,accessed};
}
test('minimal useful answer is accepted without personal information',()=>{
 assert.deepEqual(validateAnswers({problem:'  code and library disagree  '}),{role:'',size:'',barrier:'',systems:[],tools:[],problem:'code and library disagree',stack:'',approval:''});
});
test('empty, unknown, conflicting and overlong answers are rejected',()=>{
 for(const value of [null,[],{}, {email:'person@example.test'},{role:'made-up'}, {systems:['Mac','not sure']},{tools:['other','other']},{problem:'a'.repeat(1501)},{approval:'a'.repeat(1001)},{problem:'\u0000'}])assert.equal(validateAnswers(value),null);
});
test('availability is read-only, returns no service configuration, and defaults paused',async()=>{
 const r=await request(null,{method:'GET',config:{...env,TEAM_RESEARCH_ENABLED:undefined}});assert.deepEqual(r.result,{ok:true,collecting:false,contact:false});assert.equal(r.accessed,false);assert.equal(r.headers['cache-control'],'no-store');
});
test('cross-origin, non-JSON, malformed and oversized requests never reach storage',async()=>{
 for(const [body,opts,status] of [[{}, {origin:'https://bad.test'},403],[{}, {type:'text/plain'},415],['{bad',{},400],['x'.repeat(12001),{},413],[{}, {method:'PUT'},405]]){
  const r=await request(body,opts);assert.equal(r.status,status);assert.equal(r.accessed,false);
 }
});
test('save requires a useful bounded response and rejects extra fields',async()=>{
 const r=await request({operation:'save',token:key,answers:{}});assert.equal(r.status,400);
 const extra=await request({operation:'save',token:key,answers:{problem:'test'},email:'no@example.test'});assert.equal(extra.status,400);assert.equal(extra.accessed,false);
});
test('save delegates sanitized answers and reports only successful persistence',async()=>{
 let saved;const store={budget:async()=>true,save:async(token,answers)=>{saved={token,answers};return 'saved';}};
 const r=await request({operation:'save',token:key,answers:{problem:'  test  '}},{store});assert.equal(r.status,201);assert.equal(saved.answers.problem,'test');assert.equal(saved.token,key);
 const failed=await request({operation:'save',token:key,answers:{problem:'test'}},{store:{...store,save:async()=>{throw new Error('database failure');}}});assert.equal(failed.status,502);assert.equal(failed.result.ok,undefined);
});
test('follow-up rejects absent and mismatched purpose-specific consent',async()=>{
 for(const fields of [{consent:false,consentVersion:'team-research-contact-v1'},{consent:true,consentVersion:'pro-interest-v1'}]){
  const r=await request({operation:'contact',token:key,email:'person@example.test',...fields});assert.equal(r.status,400);
 }
});
test('mail delivery failure preserves survey and revokes pending email capability',async()=>{
 let cleared;const store={budget:async()=>true,contact:async()=>key,deliveryFailed:async token=>{cleared=token;}};
 const r=await request({operation:'contact',token:key,email:'person@example.test',consent:true,consentVersion:'team-research-contact-v1'},{store,mailer:async()=>{throw new Error('mail failed');}});
 assert.equal(r.status,502);assert.equal(cleared,key);assert.match(r.result.error,/answers are saved/);
});
test('mail links carry capabilities in fragments, not query strings',async()=>{
 let mail;const store={budget:async()=>true,contact:async()=>key};
 const r=await request({operation:'contact',token:key,email:' Person@Example.test ',consent:true,consentVersion:'team-research-contact-v1'},{store,mailer:async(config,email,links)=>{mail={email,links};}});
 assert.equal(r.status,202);assert.equal(mail.email,'person@example.test');assert.equal(new URL(mail.links.confirm).search,'');assert.equal(new URL(mail.links.manage).hash,`#${key}`);
});
test('rate-limited requests cannot save or send',async()=>{
 const store={budget:async()=>false};const r=await request({operation:'save',token:key,answers:{problem:'test'}},{store});assert.equal(r.status,429);assert.equal(r.headers['retry-after'],'60');
});
test('paused collection permits deletion and withdrawal without a mail service',async()=>{
 for(const operation of ['withdraw','erase']){let acted=false;const r=await request({operation,token:key},{config:{...env,TEAM_RESEARCH_ENABLED:'false',RESEND_API_KEY:''},store:{[operation]:async()=>{acted=true;}}});assert.equal(r.status,200);assert.equal(acted,true);}
 const r=await request({operation:'save',token:key,answers:{problem:'test'}},{config:{...env,TEAM_RESEARCH_ENABLED:'false'}});assert.equal(r.status,503);assert.equal(r.accessed,false);
});
test('invalid or consumed confirmation never reports success',async()=>{
 const r=await request({operation:'confirm',token:key},{store:{confirm:async()=>false}});assert.equal(r.status,400);
});
