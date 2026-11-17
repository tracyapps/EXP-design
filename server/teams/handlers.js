import { createHash } from 'node:crypto';
import { sendJson, interestConfiguration } from '../interest/handlers.js';
import { validToken } from '../interest/store.js';
import { configuredTeamStore } from './store.js';
import { validateAnswers } from './schema.js';

async function sendContact(config, email, links) {
  const response = await fetch('https://api.resend.com/emails', {
    method:'POST', headers:{authorization:`Bearer ${config.apiKey}`,'content-type':'application/json'},
    signal:AbortSignal.timeout(5000), body:JSON.stringify({from:config.from,to:email,
      subject:'One quick check — EXP team research',
      text:`You asked to hear from tracy about your EXP team-research response.\n\nConfirm within 24 hours:\n${links.confirm}\n\nThis only gives permission for research follow-up. No newsletter, Pro mailing list, account, or purchase.\n\nStop follow-up or delete your response:\n${links.manage}\n\nKeep that private link: it controls this response. Opening either link alone changes nothing. If this wasn't you, ignore this email; there will be no research follow-up without confirmation.`})
  });
  if (!response.ok || !(await response.json())?.id) throw new Error('mail unavailable');
}
export function createTeamHandler({env=process.env,storeFactory=configuredTeamStore,mailer=sendContact}={}) {
  return async (request,response) => {
    const config = interestConfiguration(env,'withdraw'); // origin/DB only; independent of Pro enrollment
    const collecting = env.TEAM_RESEARCH_ENABLED === 'true' && env.TEAM_RESEARCH_POLICY === 'team-research-90d-v1';
    const contactReady = Boolean(config?.apiKey && config?.from);
    if (request.method==='GET') return sendJson(response,{ok:true,collecting:Boolean(config && collecting),contact:contactReady && collecting});
    if (request.method!=='POST') { response.setHeader('allow','GET, POST'); return sendJson(response,{error:'method not allowed'},405); }
    if (!config) return sendJson(response,{error:"the survey is taking a break. please try again later."},503);
    if (request.headers?.origin!==config.origin) return sendJson(response,{error:'invalid request origin'},403);
    if (!/^application\/json(?:;|$)/i.test(request.headers?.['content-type'] || '')) return sendJson(response,{error:'send JSON'},415);
    let body;
    try {
      const raw=typeof request.body==='string' ? request.body : JSON.stringify(request.body);
      if (!raw || Buffer.byteLength(raw)>12000) return sendJson(response,{error:'that response is too long.'},413);
      body=JSON.parse(raw);
      if (!body || typeof body!=='object' || Array.isArray(body)) throw new Error();
    } catch { return sendJson(response,{error:'could not read that response.'},400); }
    const {operation,token}=body;
    if (!['save','contact','confirm','withdraw','erase'].includes(operation) || !validToken(token))
      return sendJson(response,{error:'this request is missing a valid private link.'},400);
    if (['save','contact','confirm'].includes(operation) && !collecting)
      return sendJson(response,{error:"the survey is taking a break. your answers are still on this page."},503);
    const allowed={save:['answers','website'],contact:['email','consent','consentVersion'],confirm:[],withdraw:[],erase:[]}[operation];
    if (Object.keys(body).some(key=>!['operation','token',...allowed].includes(key))) return sendJson(response,{error:'unexpected fields'},400);
    try {
      const store=storeFactory(config.databaseURL);
      if (operation==='save') {
        if (body.website!==undefined && typeof body.website!=='string') return sendJson(response,{error:'invalid request'},400);
        if (body.website) return sendJson(response,{error:'could not save this response.'},400);
        const answers=validateAnswers(body.answers);
        if (!answers) return sendJson(response,{error:'answer at least one question, and check the field lengths.'},400);
        if (!await store.budget('save',60,60)) {response.setHeader('retry-after','60');return sendJson(response,{error:'a lot of responses just arrived. please try again in a minute.'},429);}
        const saved=await store.save(token,answers);
        if (saved==='expired') return sendJson(response,{error:'this response has expired. reload to start a new one.'},410);
        return sendJson(response,{ok:true,state:saved},saved==='already_saved'?200:201);
      }
      if (operation==='contact') {
        if (!contactReady) return sendJson(response,{error:"your answers are saved, but email isn't available right now. you can try again later using your private link."},503);
        if (body.consent!==true || body.consentVersion!=='team-research-contact-v1' || typeof body.email!=='string' ||
          body.email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email.trim())) return sendJson(response,{error:'check your email address and the research follow-up permission.'},400);
        const email=body.email.trim().toLowerCase();
        if (!await store.budget('contact',30,60) || !await store.budget(`email:${createHash('sha256').update(email).digest('hex')}`,3,3600))
          return sendJson(response,{error:'please wait before requesting another email.'},429);
        const confirmation=await store.contact(token,email);
        if (confirmation) {
          try { await mailer(config,email,{confirm:`${config.origin}/teams/confirm#${confirmation}`,manage:`${config.origin}/teams/manage#${token}`}); }
          catch { await store.deliveryFailed(confirmation); return sendJson(response,{error:"your answers are saved. the email didn't go through—please try again."},502); }
        }
        return sendJson(response,{ok:true,state:'pending'},202);
      }
      if (operation==='confirm') {
        if (!await store.confirm(token)) return sendJson(response,{error:'this link was used, cancelled, or expired. use your private response link to request another.'},400);
        return sendJson(response,{ok:true,state:'confirmed'});
      }
      await store[operation](token);
      return sendJson(response,{ok:true,state:operation==='erase'?'erased':'withdrawn'});
    } catch {
      console.warn('Team research operation unavailable'); // no answers, addresses or capabilities in logs
      return sendJson(response,{error:'could not finish that. please try again.'},502);
    }
  };
}
