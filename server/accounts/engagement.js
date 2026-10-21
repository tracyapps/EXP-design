import { randomBytes } from 'node:crypto';

export const engagementActions = {
  engagement: [], 'submit-member-feedback': ['id','kind','subject','message','testimonial','firstName','lastInitial','consentVersion'],
  'withdraw-testimonial': ['id'], 'delete-member-feedback': ['id'],
  'record-member-share': ['id','target','code'], 'clear-member-shares': [],
  'claim-referral': ['code','consent','consentVersion'], 'withdraw-referral-credit': []
};
export const referralCode = value => typeof value==='string' && /^[A-Za-z0-9_-]{32}$/.test(value);
const uuid = value => typeof value==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
const text = (value,max) => typeof value==='string' && value.length<=max && value.trim().length>0;
const result = (body,status=200)=>({body,status});
const targets = ['copy','system','email','linkedin','bluesky','facebook','mastodon'];

export async function handleEngagement({pool,userId,body,enabled}) {
  const action=body.action;
  if (['submit-member-feedback','withdraw-testimonial','delete-member-feedback','record-member-share'].includes(action) && !uuid(body.id)) return result({error:'Invalid private record reference.'},400);
  if(action==='record-member-share' && (!targets.includes(body.target) || !referralCode(body.code)))return result({error:'Choose a supported sharing action.'},400);
  let attribution=null;
  if(action==='submit-member-feedback') {
    if(!['feedback','feature'].includes(body.kind) || !text(body.subject,120) || !text(body.message,1500) || typeof body.testimonial!=='boolean')return result({error:'Choose feedback or a feature request, and enter a subject and message within the limits.'},400);
    if(body.testimonial) {
      if(!text(body.firstName,60) || !text(body.lastInitial,2) || !/^\p{L}$/u.test(body.lastInitial.normalize('NFC')) || body.consentVersion!=='testimonial-v1')return result({error:'Preview your first name and last initial, then choose the current testimonial permission.'},400);
      attribution=`${body.firstName.trim()} ${body.lastInitial.normalize('NFC').toLocaleUpperCase()}.`;
    } else if(body.firstName || body.lastInitial || body.consentVersion) return result({error:'Attribution details require your optional testimonial permission.'},400);
  }
  if(action==='claim-referral' && (!referralCode(body.code) || body.consent!==true || body.consentVersion!=='referral-credit-v1'))return result({error:'Choose whether to credit the member who shared this link using the current form.'},400);
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const member=(await client.query('SELECT id,"createdAt" FROM exp_member_user WHERE id=$1 FOR UPDATE',[userId])).rows[0];
    if(!member){await client.query('ROLLBACK');return result({error:'Please sign in again.'},401);}
    const ready=(await client.query("SELECT to_regclass('public.exp_member_feedback') IS NOT NULL AS ready")).rows[0].ready;
    if(!ready){await client.query('ROLLBACK');return action==='engagement'?result({ok:true,enabled:false,feedback:[],shareCode:null,shareActions:0,creditedSignups:0,referral:null}):result({error:'Account feedback and sharing are not available yet.'},503);}
    const response=await perform(member); await client.query('COMMIT'); return response;
  }catch(error){await client.query('ROLLBACK');if(error.code==='23505')return result({error:'That record reference is already in use. Refresh and try again.'},409);throw error;}
  finally{client.release();}

  async function slot(){return (await client.query(`INSERT INTO exp_member_engagement_limit(user_id,window_start,count) VALUES($1,now(),1)
    ON CONFLICT(user_id) DO UPDATE SET window_start=CASE WHEN exp_member_engagement_limit.window_start<=now()-interval '1 hour' THEN now() ELSE exp_member_engagement_limit.window_start END,
    count=CASE WHEN exp_member_engagement_limit.window_start<=now()-interval '1 hour' THEN 1 ELSE exp_member_engagement_limit.count+1 END
    WHERE exp_member_engagement_limit.window_start<=now()-interval '1 hour' OR exp_member_engagement_limit.count<60 RETURNING user_id`,[userId])).rowCount>0;}
  async function perform(member){
    if(action==='engagement') {
      if(enabled)await client.query('INSERT INTO exp_member_share_link(user_id,code) VALUES($1,$2) ON CONFLICT(user_id) DO NOTHING',[userId,randomBytes(24).toString('base64url')]);
      const feedback=(await client.query('SELECT id,kind,subject,message,testimonial_allowed,testimonial_name,accepted_at,withdrawn_at,created_at FROM exp_member_feedback WHERE user_id=$1 ORDER BY created_at DESC,id LIMIT 50',[userId])).rows;
      const link=(await client.query('SELECT code FROM exp_member_share_link WHERE user_id=$1',[userId])).rows[0];
      const shares=(await client.query('SELECT count(*)::integer AS count FROM exp_member_share_event WHERE user_id=$1',[userId])).rows[0].count;
      const credits=(await client.query('SELECT count(*)::integer AS count FROM exp_member_referral_credit WHERE referrer_id=$1 AND withdrawn_at IS NULL',[userId])).rows[0].count;
      const referral=(await client.query('SELECT accepted_at,withdrawn_at,referrer_id IS NOT NULL AS active FROM exp_member_referral_credit WHERE user_id=$1',[userId])).rows[0];
      return result({ok:true,enabled,feedback:feedback.map(r=>({id:r.id,kind:r.kind,subject:r.subject,message:r.message,testimonial:r.testimonial_allowed,attribution:r.testimonial_name,acceptedAt:r.accepted_at,withdrawnAt:r.withdrawn_at,createdAt:r.created_at})),shareCode:link?.code??null,shareActions:shares,creditedSignups:credits,referral:referral?{active:referral.active&&!referral.withdrawn_at,withdrawnAt:referral.withdrawn_at}:null});
    }
    if(action==='withdraw-testimonial') {
      const r=await client.query('UPDATE exp_member_feedback SET testimonial_allowed=false,testimonial_name=NULL,withdrawn_at=now() WHERE id=$1 AND user_id=$2 RETURNING id',[body.id,userId]);return r.rowCount?result({ok:true}):result({error:'Feedback not found.'},404);
    }
    if(action==='delete-member-feedback')return (await client.query('DELETE FROM exp_member_feedback WHERE id=$1 AND user_id=$2 RETURNING id',[body.id,userId])).rowCount?result({ok:true}):result({error:'Feedback not found.'},404);
    if(action==='clear-member-shares'){await client.query('DELETE FROM exp_member_share_event WHERE user_id=$1',[userId]);return result({ok:true});}
    if(action==='withdraw-referral-credit'){await client.query('UPDATE exp_member_referral_credit SET referrer_id=NULL,withdrawn_at=COALESCE(withdrawn_at,now()) WHERE user_id=$1',[userId]);return result({ok:true});}
    if(!enabled)return result({error:'New feedback, sharing records and signup credit are paused. You can still withdraw permission or delete your records.'},503);
    if(action==='claim-referral') {
      const prior=(await client.query('SELECT referrer_id,withdrawn_at FROM exp_member_referral_credit WHERE user_id=$1',[userId])).rows[0];
      const link=(await client.query('SELECT user_id FROM exp_member_share_link WHERE code=$1',[body.code])).rows[0];
      if(!link || link.user_id===userId)return result({error:'This share link cannot be credited. Your account still works normally.'},400);
      if(prior)return !prior.withdrawn_at&&prior.referrer_id===link.user_id?result({ok:true}):result({error:'Referral credit was already chosen or withdrawn. It cannot be reassigned.'},409);
      if(Date.now()-new Date(member.createdAt).getTime()>86400000)return result({error:'Signup credit is available only during the first 24 hours of a new account.'},409);
      if(!await slot())return result({error:'Too many changes. Please try again later.'},429);
      await client.query("INSERT INTO exp_member_referral_credit(user_id,referrer_id,consent_version) VALUES($1,$2,'referral-credit-v1')",[userId,link.user_id]);return result({ok:true});
    }
    if(action==='record-member-share' && !(await client.query('SELECT user_id FROM exp_member_share_link WHERE user_id=$1 AND code=$2',[userId,body.code])).rowCount)return result({error:'Your member link changed. Reload your account before recording a share.'},409);
    const table=action==='record-member-share'?'exp_member_share_event':'exp_member_feedback';
    const prior=(await client.query(`SELECT * FROM ${table} WHERE id=$1`,[body.id])).rows[0];
    if(prior){const same=prior.user_id===userId&&(action==='record-member-share'?prior.target===body.target:prior.kind===body.kind&&prior.subject===body.subject.trim()&&prior.message===body.message.trim()&&prior.testimonial_allowed===body.testimonial&&prior.testimonial_name===attribution);return same?result({ok:true}):result({error:'That record reference is already in use. Refresh and try again.'},409);}
    const count=(await client.query(`SELECT count(*)::integer AS count FROM ${table} WHERE user_id=$1`,[userId])).rows[0].count;
    if(count>=(action==='record-member-share'?1000:50))return result({error:action==='record-member-share'?'Clear your share-action history before recording more actions.':'You have 50 saved feedback notes. Delete an old note before adding another.'},409);
    if(!await slot())return result({error:'Too many changes. Please try again in an hour.'},429);
    if(action==='record-member-share')await client.query('INSERT INTO exp_member_share_event(id,user_id,target) VALUES($1,$2,$3)',[body.id,userId,body.target]);
    else await client.query(`INSERT INTO exp_member_feedback(id,user_id,kind,subject,message,testimonial_allowed,testimonial_name,consent_version,accepted_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,CASE WHEN $6 THEN now() ELSE NULL END)`,[body.id,userId,body.kind,body.subject.trim(),body.message.trim(),body.testimonial,attribution,body.testimonial?'testimonial-v1':null]);
    return result({ok:true});
  }
}
