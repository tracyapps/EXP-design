import React,{useEffect,useRef,useState} from 'react';
import {Avatar} from './AccountMenu.jsx';

async function preparePhoto(file) {
  if(!['image/png','image/jpeg','image/webp'].includes(file.type) || file.size>5*1024*1024)throw new Error('Choose a PNG, JPEG or WebP photo up to 5 MB.');
  const bitmap=await createImageBitmap(file);
  try{
    if(bitmap.width*bitmap.height>40000000)throw new Error('That photo is too large. Choose one under 40 megapixels.');
    const canvas=document.createElement('canvas');canvas.width=256;canvas.height=256;
    const side=Math.min(bitmap.width,bitmap.height);
    canvas.getContext('2d').drawImage(bitmap,(bitmap.width-side)/2,(bitmap.height-side)/2,side,side,0,0,256,256);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/webp',.82));
    if(!blob || blob.size>98304)throw new Error('Could not prepare that photo. Please try another image.');
    return await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(new Error('Could not read that photo.'));reader.readAsDataURL(blob);});
  }finally{bitmap.close();}
}
export default function ProfilePhoto({user,busy,onSave}) {
  const [draft,setDraft]=useState(null),[processing,setProcessing]=useState(false),[message,setMessage]=useState('');
  const [focusTarget,setFocusTarget]=useState(null);
  const input=useRef(null),saveButton=useRef(null),removeButton=useRef(null),generation=useRef(0);
  useEffect(()=>{
    if(busy || !focusTarget)return;
    (focusTarget==='input'?input:focusTarget==='save'?saveButton:removeButton).current?.focus();
    setFocusTarget(null);
  },[busy,focusTarget]);
  async function choose(file) {
    const version=++generation.current;setDraft(null);setMessage('');
    if(!file){setProcessing(false);return;}
    setProcessing(true);
    try{const next=await preparePhoto(file);if(version===generation.current)setDraft(next);}
    catch(error){if(version===generation.current)setMessage(error.message);}
    finally{if(version===generation.current)setProcessing(false);}
  }
  async function save(action) {
    if(await onSave(action==='save-avatar'?{action,image:draft}:{action})) {setDraft(null);if(input.current)input.current.value='';setFocusTarget('input');}
    else setFocusTarget(action==='save-avatar'?'save':'remove');
  }
  return <section className="account-card" aria-labelledby="profile-photo-title">
    <h2 id="profile-photo-title">Profile photo</h2>
    <div className="profile-photo-preview"><Avatar user={{...user,avatar:draft??user.avatar}}/></div>
    <p>Your photo appears in your account menu. It stays private and is not published with your community profile.</p>
    <label htmlFor="profile-photo">Choose a profile photo (PNG, JPEG or WebP, up to 5 MB)</label>
    <input id="profile-photo" ref={input} type="file" accept="image/png,image/jpeg,image/webp" disabled={busy} onChange={e=>choose(e.target.files?.[0])}/>
    <p>Preview a centered square crop, shown as a circle. Only the small cropped photo is uploaded when you save; the original stays on your device.</p>
    <p role="status">{processing?'Preparing photo…':message}</p>
    <div className="account-session-actions">
      {draft && <button type="button" ref={saveButton} disabled={busy||processing} onClick={()=>save('save-avatar')}>Save profile photo</button>}
      {draft && <button type="button" className="account-secondary" disabled={busy} onClick={()=>{generation.current++;setDraft(null);setProcessing(false);input.current.value='';input.current.focus();}}>Cancel photo change</button>}
      {user.avatar && <button type="button" ref={removeButton} className="account-secondary" disabled={busy||processing} onClick={()=>save('remove-avatar')}>Remove profile photo</button>}
    </div>
  </section>;
}
