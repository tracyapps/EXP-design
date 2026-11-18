import { createHash } from 'node:crypto';
import { teamResearchOwnerEmail } from '../accounts/team-research.js';

export function ownerNotificationMessage(config, id) {
  return { from: config.from, to: teamResearchOwnerEmail,
    subject: 'a new EXP team-research response',
    text: `someone answered the team survey. :)\n\nsign in to read the responses:\n${config.origin}/account/team-research\n\nResponse reference: ${id}\n\nThe response and any contact details stay in your private account inbox. Follow-up email addresses only appear there after the person confirms permission.` };
}
export async function sendOwnerNotification(config, message, idempotencyKey) {
  const response = await fetch('https://api.resend.com/emails', {
    method:'POST', signal:AbortSignal.timeout(5000),
    headers:{authorization:`Bearer ${config.apiKey}`,'content-type':'application/json','Idempotency-Key':idempotencyKey},
    body:JSON.stringify(message),
  });
  const result=await response.json().catch(()=>null);
  if(!response.ok || typeof result?.id!=='string' || !result.id) throw new Error('Owner notification unavailable');
}
// One record at a time: a database lease prevents competing request/job workers
// from sending concurrently. Provider idempotency additionally covers 24h retries.
export async function notifyOwner({store,config,send=sendOwnerNotification,capability=null}) {
  const pending=await store.claimOwnerNotification(capability);
  if(!pending)return {sent:0,failed:0};
  try {
    await send(config,ownerNotificationMessage(config,pending.id),`team-research-owner/${createHash('sha256').update(config.origin).digest('hex').slice(0, 16)}/${pending.id}`);
  } catch {
    await store.finishOwnerNotification(pending.claim,false);
    return {sent:0,failed:1};
  }
  await store.finishOwnerNotification(pending.claim,true);
  return {sent:1,failed:0};
}
