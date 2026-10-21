import {normalizePhoto,privateAvatar} from './avatar.js';
export const communityVersion = 'community-profile-v1';
export const communityActions = { community: [], 'check-community-handle':['handle'], 'save-community': ['handle','displayName','bio','link','photo','usePrivatePhoto'],
  'publish-community': ['revision','confirmed','consentVersion'], 'unpublish-community': [], 'report-community': ['handle','category','reason'] };
const reserved = new Set(['admin','administrator','api','account','accounts','community','delete','developer','download','exp','help','login','moderator','news','people','privacy','pro','profile','settings','signup','staff','support','system','tapps','team','terms']);
export const validHandle = handle => typeof handle === 'string' && /^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$/.test(handle) && !reserved.has(handle);
// The owner's brand handle is readable/reportable only after an operator-bound
// reservation permits saving it. Other reserved names remain unavailable.
const profileHandle = handle => validHandle(handle) || handle === 'tapps';
const handleProblem = handle => {
  if(typeof handle!=='string' || !/^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$/.test(handle))return 'Handle must be 3–30 lowercase letters, numbers or hyphens, and start and end with a letter or number.';
  if(reserved.has(handle) && handle!=='tapps')return 'That handle is reserved. Choose a different handle.';
  return null;
};
const text = (value, max, required=false) => typeof value === 'string' && value.length <= max && (!required || value.trim().length > 0);
const result = (body, status=200) => ({ body, status });
// The only public projection. No account identity, email, permissions, drafts or reports.
export const publicProfile = row => ({ handle: row.handle, displayName: row.published_name, bio: row.published_bio, link: row.published_link, photo:privateAvatar(row.published_photo) });

export async function handleCommunity({ pool, userId, body, enabled }) {
  const { action } = body;
  const handle = typeof body.handle === 'string' ? body.handle.trim().toLowerCase() : body.handle;
  if (action === 'save-community') {
    const problem=handleProblem(handle);
    if(problem)return result({error:problem+' Your entered details have not been saved.',field:'handle'},400);
    if(!text(body.displayName,80,true))return result({error:'Public display name is required and must be no more than 80 characters.',field:'displayName'},400);
    if(!text(body.bio,500))return result({error:'Public bio must be no more than 500 characters.',field:'bio'},400);
    if(!text(body.link,300))return result({error:'Public website must be no more than 300 characters.',field:'link'},400);
    if (body.link) {
      try { const url=new URL(body.link); if(url.protocol!=='https:' || url.username || url.password) throw Error(); }
      catch { return result({ error:'Use a complete HTTPS website link without login details, or leave it empty.',field:'link' },400); }
    }
  }
  if (action === 'publish-community' && (body.confirmed!==true || body.consentVersion!==communityVersion ||
      typeof body.revision!=='string' || !/^[a-f0-9-]{36}$/.test(body.revision))) return result({ error:'Preview the saved profile and confirm public publication.' },400);
  if (action === 'report-community' && (!profileHandle(handle) || !['spam','harassment','privacy','other'].includes(body.category) || !text(body.reason,500,true))) return result({ error:'Choose a report category and add a reason up to 500 characters.' },400);
  if(action==='save-community' && ((body.photo!==undefined && body.photo!==null && typeof body.photo!=='string') || (body.usePrivatePhoto!==undefined && typeof body.usePrivatePhoto!=='boolean') || (body.usePrivatePhoto && body.photo)))return result({error:'Choose one source for the public photo.'},400);
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const owner=await client.query('SELECT id,image FROM exp_member_user WHERE id=$1 FOR UPDATE',[userId]);
    if (!owner.rowCount) { await client.query('ROLLBACK'); return result({error:'Please sign in again.'},401); }
    const response=await perform(owner.rows[0]);
    await client.query('COMMIT'); return response;
  } catch(error) {
    await client.query('ROLLBACK');
    if(error.code==='23505') return result({error:'That handle is already taken. Choose another.',field:'handle'},409);
    throw error;
  } finally { client.release(); }

  async function slot() {
    return (await client.query(`INSERT INTO exp_member_community_limit(user_id,window_start,count) VALUES ($1,now(),1)
      ON CONFLICT(user_id) DO UPDATE SET
      window_start=CASE WHEN exp_member_community_limit.window_start<=now()-interval '1 hour' THEN now() ELSE exp_member_community_limit.window_start END,
      count=CASE WHEN exp_member_community_limit.window_start<=now()-interval '1 hour' THEN 1 ELSE exp_member_community_limit.count+1 END
      WHERE exp_member_community_limit.window_start<=now()-interval '1 hour' OR exp_member_community_limit.count<30 RETURNING user_id`,[userId])).rowCount>0;
  }
  function limited() { return result({error:'Too many changes. Please try again in an hour. You can still unpublish.'},429); }
  async function checkHandle(row) {
    const problem=handleProblem(handle);
    if(problem)return {available:false,reason:problem,status:400};
    if(row?.first_published_at && row.handle!==handle)return {available:false,reason:'A published handle cannot be renamed yet. You can edit the public details or unpublish.',status:409};
    if(handle==='tapps') {
      const ready=(await client.query("SELECT to_regclass('public.exp_member_community_reservation') IS NOT NULL AS ready")).rows[0].ready;
      const permitted=ready && (await client.query('SELECT 1 FROM exp_member_community_reservation WHERE handle=$1 AND user_id=$2',[handle,userId])).rowCount>0;
      if(!permitted)return {available:false,reason:'That handle is reserved for the verified EXP owner. Choose another handle.',status:400};
    }
    if((await client.query('SELECT 1 FROM exp_member_community WHERE handle=$1 AND user_id<>$2',[handle,userId])).rowCount)return {available:false,reason:'That handle is already taken. Choose another.',status:409};
    return {available:true,reason:'This handle is available for your account.'};
  }
  async function perform(owner) {
    const photoReady=(await client.query("SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exp_member_community' AND column_name='published_photo') AS ready")).rows[0].ready;
    const row=(await client.query('SELECT * FROM exp_member_community WHERE user_id=$1',[userId])).rows[0];
    if(action==='check-community-handle') {
      const checked=await checkHandle(row);
      return result({ok:true,handle:typeof handle==='string'?handle:null,available:checked.available,reason:checked.reason});
    }
    if(action==='community') return result({ok:true,communityOpen:enabled,photoEnabled:photoReady,publicationBlocked:row?.moderation_hold??false,
      handleLocked:Boolean(row?.first_published_at),
      draft:row?{handle:row.handle,displayName:row.display_name,bio:row.bio,link:row.link,photo:privateAvatar(row.draft_photo),revision:row.revision}:null,
      published:row?.published_at?publicProfile(row):null});
    if(action==='unpublish-community') {
      await client.query(`UPDATE exp_member_community SET published_at=NULL,published_revision=NULL,published_name=NULL,
        published_bio=NULL,published_link=NULL,publication_version=NULL${photoReady?',published_photo=NULL':''} WHERE user_id=$1`,[userId]);
      return result({ok:true});
    }
    if(action==='save-community') {
      const checked=await checkHandle(row);
      if(!checked.available)return result({error:checked.reason+' Your entered details have not been saved.',field:'handle'},checked.status);
      const changingPhoto=body.photo!==undefined || body.usePrivatePhoto===true;
      if(changingPhoto && !photoReady)return result({error:'Public photo uploads are not available yet. Your draft has not changed.'},503);
      let photo=privateAvatar(row?.draft_photo);
      if(changingPhoto){
        const source=body.usePrivatePhoto?privateAvatar(owner.image):body.photo;
        if(body.usePrivatePhoto && !source)return result({error:'Add a private profile photo first, or upload a public one.'},400);
        if(source===null)photo=null;
        else try{photo=await normalizePhoto(source);}catch{return result({error:'Choose a still PNG, JPEG or WebP photo. Your draft has not changed.'},400);}
      }
      if(row && (!photoReady || photo===privateAvatar(row.draft_photo)) && row.handle===handle && row.display_name===body.displayName.trim() && row.bio===body.bio.trim() && row.link===body.link.trim()) return result({ok:true});
      if(!await slot()) return limited();
      await client.query(`INSERT INTO exp_member_community(user_id,handle,display_name,bio,link) VALUES($1,$2,$3,$4,$5)
        ON CONFLICT(user_id) DO UPDATE SET handle=$2,display_name=$3,bio=$4,link=$5,revision=pg_catalog.gen_random_uuid()`,
      [userId,handle,body.displayName.trim(),body.bio.trim(),body.link.trim()]);
      if(photoReady)await client.query('UPDATE exp_member_community SET draft_photo=$2 WHERE user_id=$1',[userId,photo]);
      return result({ok:true});
    }
    if(action==='publish-community') {
      if(!enabled) return result({error:'Public community profiles are not open right now. Drafts and unpublishing remain available.'},503);
      if(row?.moderation_hold) return result({error:'Publication of this profile is paused for moderation.'},403);
      if(!row || row.revision!==body.revision) return result({error:'The saved draft changed. Save and preview it again before publishing.'},409);
      if(row.published_revision===row.revision) return result({ok:true});
      if(!await slot()) return limited();
      await client.query(`UPDATE exp_member_community SET first_published_at=COALESCE(first_published_at,now()),published_at=now(),
        published_revision=revision,published_name=display_name,published_bio=bio,published_link=link,publication_version=$2${photoReady?',published_photo=draft_photo':''} WHERE user_id=$1`,[userId,communityVersion]);
      return result({ok:true});
    }
    if(!enabled) return result({error:'Community reports are not open right now.'},503);
    const target=(await client.query('SELECT * FROM exp_member_community WHERE handle=$1 AND published_at IS NOT NULL AND NOT moderation_hold',[handle])).rows[0];
    if(!target) return result({error:'Profile not found.'},404);
    if(target.user_id===userId) return result({error:'You can unpublish your own profile from your account.'},400);
    if((await client.query('SELECT id FROM exp_member_community_report WHERE reporter_id=$1 AND target_id=$2 AND target_revision=$3',[userId,target.user_id,target.published_revision])).rowCount) return result({ok:true});
    if(!await slot()) return limited();
    await client.query(`INSERT INTO exp_member_community_report(reporter_id,target_id,target_revision,category,reason,public_snapshot) VALUES($1,$2,$3,$4,$5,$6)`,
      [userId,target.user_id,target.published_revision,body.category,body.reason.trim(),JSON.stringify(publicProfile(target))]);
    return result({ok:true});
  }
}

export function createPublicProfileHandler({ pool, enabled=false }) {
  const headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex'};
  const json=(body,status=200)=>Response.json(body,{status,headers});
  return async request=>{
    if(request.method!=='GET') return Response.json({error:'Use GET.'},{status:405,headers:{...headers,Allow:'GET'}});
    const url=new URL(request.url), handle=url.searchParams.get('handle');
    if(!enabled || !profileHandle(handle) || url.searchParams.getAll('handle').length!==1) return json({error:'Profile not found.'},404);
    try {
      const row=(await pool.query(`SELECT handle,published_name,published_bio,published_link,to_jsonb(exp_member_community)->>'published_photo' AS published_photo FROM exp_member_community
        WHERE handle=$1 AND published_at IS NOT NULL AND NOT moderation_hold`,[handle])).rows[0];
      return row?json({ok:true,profile:publicProfile(row)}):json({error:'Profile not found.'},404);
    } catch { return json({error:'Community profiles are unavailable. Please try later.'},503); }
  };
}
