import test from 'node:test';
import assert from 'node:assert/strict';
import {canReviewTeamResearch,handleTeamResearch} from '../server/accounts/team-research.js';
import {ownerNotificationMessage,notifyOwner} from '../server/teams/notifications.js';
import {createTeamJobHandler} from '../server/teams/jobs.js';
import {createTeamHandler} from '../server/teams/handlers.js';
const owner={id:'owner-id',email:'tracyapps@gmail.com',emailVerified:true};
const config={origin:'https://example.test',from:'EXP <hello@example.test>',apiKey:'test-only'};
const env={CRON_SECRET:'s'.repeat(40),EXP_INTEREST_DATABASE_URL:'test-only',INTEREST_PUBLIC_ORIGIN:config.origin,TEAM_RESEARCH_POLICY:'team-research-90d-v1',TEAM_RESEARCH_NOTIFY_OWNER:'true',RESEND_API_KEY:config.apiKey,SIGNUP_FROM_EMAIL:config.from};
async function invoke(handler,request){let output;const headers={};const response={statusCode:200,setHeader:(k,v)=>headers[k]=v,end:value=>output=JSON.parse(value)};await handler(request,response);return{status:response.statusCode,body:output,headers};}
test('only the verified owner mailbox qualifies; no Gmail alias guessing',()=>{
 assert.equal(canReviewTeamResearch(owner),true);assert.equal(canReviewTeamResearch({...owner,email:'TRACYAPPS@gmail.com'}),true);
 for(const user of [null,{}, {...owner,id:null},{...owner,emailVerified:false},{...owner,emailVerified:'true'},{...owner,email:'someone@example.test'},{...owner,email:'tracyapps+research@gmail.com'},{...owner,email:'tracy.apps@gmail.com'}])assert.equal(canReviewTeamResearch(user),false);
});
test('non-owner inbox request cannot touch the research database',async()=>{
 let read=false;const result=await handleTeamResearch({user:{...owner,email:'other@example.test'},body:{email:owner.email},store:{listResponses:async()=>{read=true;}}});assert.equal(result.status,403);assert.equal(read,false);
});
test('owner request validates pagination and has a clear unavailable state',async()=>{
 assert.equal((await handleTeamResearch({user:owner,body:{},store:null})).status,503);
 for(const before of [0,'0','-1','9223372036854775808','oops',{},'1;SELECT 1'])assert.equal((await handleTeamResearch({user:owner,body:{before},store:null})).status,400);
 let cursor;const result=await handleTeamResearch({user:owner,body:{before:'26'},store:{listResponses:async before=>{cursor=before;return{responses:[],nextBefore:null};}}});assert.equal(result.status,200);assert.equal(cursor,'26');
});
test('owner notification contains a login link, not survey answers or respondent email',()=>{
 const message=ownerNotificationMessage(config,'42');assert.equal(message.to,owner.email);assert.match(message.text,/https:\/\/example.test\/account\/team-research/);assert.ok(!message.text.includes('#'));assert.equal(Object.keys(message).sort().join(','),'from,subject,text,to');
});
test('claimed notification is settled only after accepted delivery, with a stable provider key',async()=>{
 const events=[];const store={claimOwnerNotification:async capability=>{events.push(['claim',capability]);return{id:'42',claim:'lease-1'};},finishOwnerNotification:async(...args)=>events.push(['finish',...args])};
 const result=await notifyOwner({store,config,capability:'private-token',send:async(c,message,key)=>{events.push(['send',key]);assert.equal(message.to,owner.email);}});
 assert.deepEqual(events,[['claim','private-token'],['send',events[1][1]],['finish','lease-1',true]]);assert.match(events[1][1],/^team-research-owner\/[a-f0-9]{16}\/42$/);assert.deepEqual(result,{sent:1,failed:0});
});
test('failed delivery stays retryable; already-claimed or delivered rows produce no mail',async()=>{
 let settled;const store={claimOwnerNotification:async()=>({id:'42',claim:'lease'}),finishOwnerNotification:async(...args)=>{settled=args;}};
 assert.deepEqual(await notifyOwner({store,config,send:async()=>{throw new Error('offline');}}),{sent:0,failed:1});assert.deepEqual(settled,['lease',false]);
 assert.deepEqual(await notifyOwner({store:{claimOwnerNotification:async()=>null},config,send:async()=>assert.fail('unexpected send')}),{sent:0,failed:0});
});
test('failed owner notification cannot turn a durable survey save into a failure',async()=>{
 const handler=createTeamHandler({env:{...env,TEAM_RESEARCH_ENABLED:'true'},storeFactory:()=>({budget:async()=>true,save:async()=> 'saved',claimOwnerNotification:async()=>{throw new Error('queue failure');}})});
 const result=await invoke(handler,{method:'POST',headers:{origin:config.origin,'content-type':'application/json'},body:{operation:'save',token:'a'.repeat(43),answers:{problem:'a test'}}});assert.equal(result.status,201);assert.equal(result.body.state,'saved');
});
test('cron is authenticated and rejects incorrect methods without reading data',async()=>{
 const handler=createTeamJobHandler({env,storeFactory:()=>assert.fail('must not open database')});
 assert.equal((await invoke(handler,{method:'GET',headers:{}})).status,401);
 assert.equal((await invoke(handler,{method:'GET',headers:{authorization:'Bearer wrong'}})).status,401);
 assert.equal((await invoke(handler,{method:'POST',headers:{authorization:`Bearer ${env.CRON_SECRET}`}})).status,405);
});
test('daily cleanup continues while collection is paused; disabled notifications send nothing',async()=>{
 let cleaned=false;const handler=createTeamJobHandler({env:{...env,TEAM_RESEARCH_ENABLED:'false',TEAM_RESEARCH_NOTIFY_OWNER:'false'},storeFactory:()=>({cleanup:async()=>{cleaned=true;return{deleted:1,cleared:2};}}),send:async()=>assert.fail('must not send')});
 const result=await invoke(handler,{method:'GET',headers:{authorization:`Bearer ${env.CRON_SECRET}`}});assert.equal(result.status,200);assert.equal(cleaned,true);assert.deepEqual(result.body.retention,{deleted:1,cleared:2});assert.equal(result.headers['cache-control'],'no-store');
});
test('cron retries a bounded batch and reports delivery failures without exposing private data',async()=>{
 let claims=0;const handler=createTeamJobHandler({env,storeFactory:()=>({cleanup:async()=>({deleted:0,cleared:0}),claimOwnerNotification:async()=>({id:String(++claims),claim:`lease-${claims}`}),finishOwnerNotification:async()=>{}}),send:async()=>{throw new Error('provider private detail');}});
 const result=await invoke(handler,{method:'GET',headers:{authorization:`Bearer ${env.CRON_SECRET}`}});assert.equal(result.status,502);assert.equal(claims,5);assert.deepEqual(result.body.notifications,{sent:0,failed:5});assert.ok(!JSON.stringify(result).includes('provider private detail'));
});
