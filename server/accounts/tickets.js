export const ticketActions = {
  tickets:['scope','before'], ticket:['id'], 'create-ticket':['id','subject','message'],
  'reply-ticket':['id','receipt','revision','message'], 'set-ticket-status':['id','receipt','revision','status'],
  'delete-ticket':['id','confirmation']
};
const uuid=value=>typeof value==='string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
const text=(value,max)=>typeof value==='string' && value.length<=max && value.trim().length>0;
const result=(body,status=200)=>({body,status});
const projection=row=>({id:row.id,subject:row.subject,status:row.status,revision:row.revision,createdAt:row.created_at,updatedAt:row.updated_at});
const missing=()=>result({error:'Ticket not found.'},404);

export async function handleTickets({pool,userId,body,enabled}) {
  const {action}=body;
  if(action==='tickets') {
    if((body.scope!==undefined && !['own','support'].includes(body.scope)) ||
        (body.before!==undefined && !uuid(body.before))) return result({error:'Invalid ticket list.'},400);
  } else if(!uuid(body.id)) return result({error:'Invalid ticket reference.'},400);
  if(action==='create-ticket' && (!text(body.subject,120) || !text(body.message,1500))) return result({error:'Add a subject up to 120 characters and a message up to 1,500.'},400);
  if(['reply-ticket','set-ticket-status'].includes(action) && (!uuid(body.receipt) || !Number.isSafeInteger(body.revision) || body.revision<1)) return result({error:'Reload the ticket before making this change.'},400);
  if(action==='reply-ticket' && !text(body.message,1500)) return result({error:'Add a reply up to 1,500 characters.'},400);
  if(action==='set-ticket-status' && !['open','closed'].includes(body.status)) return result({error:'Choose open or closed.'},400);
  if(action==='delete-ticket' && body.confirmation!=='DELETE') return result({error:'Type DELETE to remove this ticket and its replies.'},400);
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const actor=await client.query('SELECT id FROM exp_member_user WHERE id=$1 FOR UPDATE',[userId]);
    if(!actor.rowCount){await client.query('ROLLBACK');return result({error:'Please sign in again.'},401);}
    // Read grants on every action; runtime has SELECT only. In-flight actions
    // may complete if an operator revokes a grant after this authorization check.
    const staff=(await client.query('SELECT user_id FROM exp_member_support_grant WHERE user_id=$1',[userId])).rowCount>0;
    const response=await perform(staff);
    await client.query('COMMIT');return response;
  } catch(error) {
    await client.query('ROLLBACK');
    if(error.code==='23505')return result({error:'That request conflicts with a saved request. Reload before retrying.'},409);
    throw error;
  } finally{client.release();}

  async function slot() {
    return (await client.query(`INSERT INTO exp_member_ticket_limit(user_id,window_start,count) VALUES($1,now(),1)
      ON CONFLICT(user_id) DO UPDATE SET
      window_start=CASE WHEN exp_member_ticket_limit.window_start<=now()-interval '1 hour' THEN now() ELSE exp_member_ticket_limit.window_start END,
      count=CASE WHEN exp_member_ticket_limit.window_start<=now()-interval '1 hour' THEN 1 ELSE exp_member_ticket_limit.count+1 END
      WHERE exp_member_ticket_limit.window_start<=now()-interval '1 hour' OR exp_member_ticket_limit.count<30 RETURNING user_id`,[userId])).rowCount>0;
  }
  function limited(){return result({error:'Too many ticket changes. Please try again in an hour. Closing and deletion remain available.'},429);}
  async function audit(id,action){await client.query('INSERT INTO exp_member_support_audit(ticket_id,actor_id,action) VALUES($1,$2,$3)',[id,userId,action]);}
  async function perform(staff) {
    if(action==='tickets') {
      const support=body.scope==='support';
      if(support && !staff)return result({error:'Support access is not available for this account.'},403);
      let cursor=null;
      if(body.before){cursor=(await client.query(`SELECT updated_at::text,id FROM exp_member_ticket WHERE id=$1 AND ($2 OR user_id=$3)`,[body.before,support,userId])).rows[0];if(!cursor)return missing();}
      const rows=(await client.query(`SELECT id,subject,status,revision,created_at,updated_at FROM exp_member_ticket
        WHERE ($1 OR user_id=$2) AND ($3::timestamptz IS NULL OR (updated_at,id)<($3,$4::uuid))
        ORDER BY updated_at DESC,id DESC LIMIT 26`,[support,userId,cursor?.updated_at??null,cursor?.id??null])).rows;
      return result({ok:true,ticketsOpen:enabled,canSupport:staff,tickets:rows.slice(0,25).map(projection),next:rows.length>25?rows[24].id:null});
    }
    const row=(await client.query('SELECT * FROM exp_member_ticket WHERE id=$1 FOR UPDATE',[body.id])).rows[0];
    const own=row?.user_id===userId;
    if(action==='create-ticket') {
      if(row){
        if(!own)return missing();
        const first=(await client.query("SELECT message FROM exp_member_ticket_event WHERE ticket_id=$1 AND kind='opened'",[body.id])).rows[0];
        return row.subject===body.subject.trim() && first?.message===body.message.trim()?result({ok:true,id:row.id}):result({error:'That request was already used for different content.'},409);
      }
      if(!enabled)return result({error:'New tickets and replies are paused. Existing threads remain readable.'},503);
      if((await client.query('SELECT id FROM exp_member_ticket WHERE user_id=$1 LIMIT 50',[userId])).rowCount>=50)return result({error:'You have reached 50 saved tickets. Delete an old ticket before opening another.'},409);
      if(!await slot())return limited();
      await client.query('INSERT INTO exp_member_ticket(id,user_id,subject) VALUES($1,$2,$3)',[body.id,userId,body.subject.trim()]);
      await client.query(`INSERT INTO exp_member_ticket_event(id,ticket_id,actor_id,actor_kind,kind,message,sequence)
        VALUES($1,$1,$2,'author','opened',$3,1)`,[body.id,userId,body.message.trim()]);
      return result({ok:true,id:body.id});
    }
    if(!row || (!own && !staff))return missing();
    if(action==='delete-ticket') {
      if(!own)return missing();
      await client.query('DELETE FROM exp_member_ticket WHERE id=$1 AND user_id=$2',[body.id,userId]);
      return result({ok:true});
    }
    if(action==='ticket') {
      if(!own)await audit(row.id,'read');
      const events=(await client.query('SELECT id,actor_kind,kind,message,sequence,created_at FROM exp_member_ticket_event WHERE ticket_id=$1 ORDER BY sequence',[row.id])).rows;
      return result({ok:true,ticketsOpen:enabled,canDelete:own,ticket:projection(row),events:events.map(event=>({id:event.id,by:event.actor_kind,kind:event.kind,message:event.message,sequence:event.sequence,createdAt:event.created_at}))});
    }
    const kind=action==='reply-ticket'?'reply':body.status, message=kind==='reply'?body.message.trim():'';
    const prior=(await client.query('SELECT ticket_id,actor_id,kind,message FROM exp_member_ticket_event WHERE id=$1',[body.receipt])).rows[0];
    if(prior)return prior.ticket_id===row.id && prior.actor_id===userId && prior.kind===kind && prior.message===message?result({ok:true}):result({error:'That request was already used. Reload the ticket.'},409);
    if(action==='set-ticket-status' && row.status===body.status)return result({ok:true});
    if(!enabled && kind!=='closed')return result({error:'New tickets and replies are paused. You can still close or delete your ticket.'},503);
    if(row.revision!==body.revision)return result({error:'This ticket changed. Refresh it before sending your change; your draft is kept.'},409);
    if(kind==='reply' && row.status==='closed')return result({error:'Reopen this ticket before replying.'},409);
    if(row.revision>=200 && kind!=='closed')return result({error:'This thread has reached its message/history limit. Open a new ticket if needed.'},409);
    if(kind!=='closed' && !await slot())return limited();
    await client.query(`INSERT INTO exp_member_ticket_event(id,ticket_id,actor_id,actor_kind,kind,message,sequence) VALUES($1,$2,$3,$4,$5,$6,$7)`,
      [body.receipt,row.id,userId,own?'author':'support',kind,message,row.revision+1]);
    await client.query('UPDATE exp_member_ticket SET status=$2,revision=revision+1,updated_at=clock_timestamp() WHERE id=$1',[row.id,action==='set-ticket-status'?body.status:row.status]);
    if(!own)await audit(row.id,kind);
    return result({ok:true});
  }
}
