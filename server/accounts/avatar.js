import sharp from 'sharp';
import {createHmac} from 'node:crypto';

export const avatarActions={'save-avatar':['image'],'remove-avatar':[]};
// Only our bounded, re-encoded first-party image is projected to the browser.
export const privateAvatar=value=>typeof value==='string' && value.length<=90000 &&
  /^data:image\/webp;base64,[A-Za-z0-9+/]+={0,2}$/.test(value)?value:null;

export async function handleAvatar({pool,userId,body,secret}) {
  if(body.action==='remove-avatar') {
    const removed=await pool.query('UPDATE exp_member_user SET image=NULL,"updatedAt"=now() WHERE id=$1 RETURNING id',[userId]);
    return {status:removed.rowCount?200:401,body:removed.rowCount?{ok:true}:{error:'Please sign in again.'}};
  }
  const key=createHmac('sha256',secret).update(`account-avatar:${userId}`).digest('hex');
  const slot=await pool.query(`INSERT INTO exp_member_mail_limit(key,sent_at,window_start,count) VALUES($1,now(),now(),1)
    ON CONFLICT(key) DO UPDATE SET sent_at=now(),
    window_start=CASE WHEN exp_member_mail_limit.window_start<=now()-interval '1 hour' THEN now() ELSE exp_member_mail_limit.window_start END,
    count=CASE WHEN exp_member_mail_limit.window_start<=now()-interval '1 hour' THEN 1 ELSE exp_member_mail_limit.count+1 END
    WHERE exp_member_mail_limit.window_start<=now()-interval '1 hour' OR exp_member_mail_limit.count<30 RETURNING key`,[key]);
  if(!slot.rowCount)return {status:429,body:{error:'Too many photo changes. Please try again in an hour. Removing your photo remains available.'}};
  let image;
  try{image=await normalizePhoto(body.image);}catch{return {status:400,body:{error:'Choose a still PNG, JPEG or WebP image. Please try another photo.'}};}
  const saved=await pool.query('UPDATE exp_member_user SET image=$2,"updatedAt"=now() WHERE id=$1 RETURNING id',
    [userId,image]);
  return {status:saved.rowCount?200:401,body:saved.rowCount?{ok:true}:{error:'Please sign in again.'}};
}

// Shared server decoder: fixed bounds, no external URLs, no metadata.
export async function normalizePhoto(value) {
  const invalid=()=>{throw new Error('invalid-photo');};
  const match=typeof value==='string' && value.length<=131104 && /^data:image\/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(value);
  if(!match)return invalid();
  const input=Buffer.from(match[2],'base64');
  if(input.length>98304 || input.toString('base64')!==match[2])return invalid();
  const type=input.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?'png':
    input[0]===255 && input[1]===216 && input[2]===255?'jpeg':
    input.subarray(0,4).toString()==='RIFF' && input.subarray(8,12).toString()==='WEBP'?'webp':null;
  // Reject SVG/other parsers before decoding, even if the MIME claims PNG.
  if(type!==match[1])return invalid();
  let output;
  try {
    const image=sharp(input,{limitInputPixels:1048576,failOn:'warning'});
    const metadata=await image.metadata();
    if(metadata.format!==type || (metadata.pages??1)!==1 || !metadata.width || !metadata.height)return invalid();
    output=await image.rotate().resize(256,256,{fit:'cover',position:'centre'}).webp({quality:82}).toBuffer();
    if(output.length>65536)return invalid();
  }catch{return invalid();}
  return `data:image/webp;base64,${output.toString('base64')}`;
}
