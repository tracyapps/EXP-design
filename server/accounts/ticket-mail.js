import { randomUUID } from 'node:crypto';

// Only references are queued with a ticket commit. The first worker attempt
// freezes a minimal envelope, so a retry always uses the same key AND payload.
const recipientSQL = `SELECT u.email,e.ticket_id,m.audience FROM exp_member_ticket_mail m
  JOIN exp_member_ticket_event e ON e.id=m.event_id
  JOIN exp_member_ticket t ON t.id=e.ticket_id
  JOIN exp_member_user u ON u.id=m.recipient_id
  LEFT JOIN exp_member_ticket_preference p ON p.user_id=u.id
  WHERE m.id=$1 AND u."emailVerified"=true AND coalesce(p.email_alerts,true)
  AND ((m.audience='author' AND t.user_id=u.id) OR
    (m.audience='support' AND EXISTS(SELECT 1 FROM exp_member_support_grant g WHERE g.user_id=u.id)))`;

function envelope(recipient, origin, from) {
  const support=recipient.audience==='support';
  return { from, to:recipient.email, subject:support?'An EXP support ticket needs attention':'EXP support replied to your ticket',
    text:`${support?'A member opened or replied to a private support ticket.':'There is a new EXP support reply to your private ticket.'}\n\nSign in to read it:\n${origin}/account/${support?'support':'tickets'}?ticket=${recipient.ticket_id}\n\nThis is a service notification, separate from news, beta and Pro emails. Ticket contents are kept out of this email. Please respond on the website; replies to this email are not added to the ticket.\n\nChange ticket email alerts in My tickets:\n${origin}/account/tickets` };
}

export function createTicketMailer({apiKey,fetcher=fetch}) {
  return async (mail,key) => {
    const response=await fetcher('https://api.resend.com/emails',{method:'POST',signal:AbortSignal.timeout(5000),
      headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(mail)});
    const receipt=await response.json().catch(()=>null);
    if(!response.ok){
      const error=new Error('Ticket notification provider rejected the request');
      error.retryable=response.status===429 || response.status>=500;
      throw error;
    }
    if(typeof receipt?.id!=='string' || !receipt.id || receipt.id.length>200)throw new Error('Ticket notification receipt unavailable');
    return receipt.id;
  };
}

export async function processTicketMail({pool,enabled=false,origin,from,send,limit=20}) {
  const counts={accepted:0,retry:0,failed:0,skipped:0};
  if(!enabled)return counts;
  const url=new URL(origin);
  if(url.origin!==origin || !['https:','http:'].includes(url.protocol) ||
      (url.protocol==='http:' && url.hostname!=='127.0.0.1') || !from || !send ||
      !Number.isSafeInteger(limit) || limit<1 || limit>100)throw new Error('Invalid ticket worker configuration');
  for(let i=0;i<limit;i++) {
    const job=await claim();
    if(!job)break;
    if(job.terminal){counts[job.terminal]++;continue;}
    // Check again immediately before the external request. An email already in
    // flight cannot be recalled if consent, a grant or a ticket changes then.
    const recipient=(await pool.query(`${recipientSQL} AND m.lease_id=$2 AND m.lease_until>now()
      AND m.first_attempt_at>now()-interval '23 hours'`,[job.id,job.lease_id])).rows[0];
    if(!recipient || recipient.email!==job.mail.to) {
      await finish(job,'skipped','ineligible');counts.skipped++;continue;
    }
    let id;
    try {
      id=await send(job.mail,`exp-ticket/${job.id}`);
      if(typeof id!=='string' || !id || id.length>200)throw new Error('Invalid provider receipt');
    } catch(error) {
      if(error.retryable===false || job.attempts>=8){
        await finish(job,'failed',error.retryable===false?'provider-rejected':'attempt-limit');counts.failed++;
      } else {
        await pool.query(`UPDATE exp_member_ticket_mail SET lease_id=NULL,lease_until=NULL,
          next_attempt_at=now()+($3*interval '1 second') WHERE id=$1 AND lease_id=$2`,
        [job.id,job.lease_id,Math.min(3600,60*2**(job.attempts-1))]);
        counts.retry++;
      }
      continue;
    }
    // If this DB acknowledgement fails, leave the committed lease/envelope.
    // A later worker can safely retry the same provider request after expiry.
    await finish(job,'accepted','accepted',id);
    counts.accepted++;
  }
  return counts;

  async function finish(job,state,outcome,providerId=null) {
    await pool.query(`UPDATE exp_member_ticket_mail SET state=$3,outcome=$4,provider_id=$5,
      finished_at=now(),mail=NULL,lease_id=NULL,lease_until=NULL WHERE id=$1 AND lease_id=$2`,[job.id,job.lease_id,state,outcome,providerId]);
  }
  async function claim() {
    const client=await pool.connect();
    try {
      await client.query('BEGIN');
      const row=(await client.query(`SELECT *,created_at<=now()-interval '7 days' OR
        first_attempt_at<=now()-interval '23 hours' AS expired FROM exp_member_ticket_mail
        WHERE state='pending' AND next_attempt_at<=now() AND (lease_until IS NULL OR lease_until<=now())
        ORDER BY next_attempt_at,id LIMIT 1 FOR UPDATE SKIP LOCKED`)).rows[0];
      if(!row){await client.query('COMMIT');return null;}
      const recipient=(await client.query(recipientSQL,[row.id])).rows[0];
      const terminal=row.expired || row.attempts>=8?'failed':!recipient || (row.mail && row.mail.to!==recipient.email)?'skipped':null;
      if(terminal) {
        await client.query(`UPDATE exp_member_ticket_mail SET state=$2,outcome=$3,finished_at=now(),mail=NULL,
          lease_id=NULL,lease_until=NULL WHERE id=$1`,[row.id,terminal,row.expired?'expired':row.attempts>=8?'attempt-limit':'ineligible']);
        await client.query('COMMIT');return {terminal};
      }
      const mail=row.mail??envelope(recipient,origin,from), lease=randomUUID();
      const claimed=(await client.query(`UPDATE exp_member_ticket_mail SET mail=$2,lease_id=$3,
        lease_until=now()+interval '2 minutes',first_attempt_at=coalesce(first_attempt_at,now()),attempts=attempts+1
        WHERE id=$1 RETURNING id,lease_id,mail,attempts`,[row.id,mail,lease])).rows[0];
      await client.query('COMMIT');return claimed;
    } catch(error){await client.query('ROLLBACK');throw error;}
    finally{client.release();}
  }
}
