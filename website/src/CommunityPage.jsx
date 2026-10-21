import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import PublicProfileCard from './PublicProfileCard.jsx';

const blank = { handle:'', displayName:'', bio:'', link:'' };
const handleHint='Use 3–30 lowercase letters, numbers or hyphens; start and end with a letter or number.';
const handleValid = value => /^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$/.test(value);
const fieldIds={handle:'community-handle',displayName:'community-name',bio:'community-bio',link:'community-link'};
function draftProblem(draft) {
  if(!handleValid(draft.handle))return {field:'handle',message:'Handle: '+handleHint};
  if(!draft.displayName.trim() || draft.displayName.length>80)return {field:'displayName',message:'Public display name is required and must be no more than 80 characters.'};
  if(draft.bio.length>500)return {field:'bio',message:'Public bio must be no more than 500 characters.'};
  if(draft.link.length>300)return {field:'link',message:'Public website must be no more than 300 characters.'};
  if(draft.link){try{const url=new URL(draft.link);if(url.protocol!=='https:' || url.username || url.password)throw Error();}catch{return {field:'link',message:'Public website: enter a complete HTTPS link, such as https://example.com, without login details, or leave it empty.'};}}
  return null;
}
const editable = value => ({handle:value.handle,displayName:value.displayName,bio:value.bio,link:value.link});
export default function CommunityPage({ request, onSignedOut }) {
  const [data,setData]=useState(null), [draft,setDraft]=useState(blank), [preview,setPreview]=useState(null);
  const [consent,setConsent]=useState(false), [busy,setBusy]=useState(false), [message,setMessage]=useState('Loading community profile…');
  const [focusTarget,setFocusTarget]=useState(null), [formError,setFormError]=useState(null);
  const [handleCheck,setHandleCheck]=useState({handle:'',state:'idle',message:''});
  const form=useRef(null), errorSummary=useRef(null), handleSequence=useRef(0);
  const currentHandle=handleCheck.handle===draft.handle?handleCheck:{handle:draft.handle,state:'checking',message:'Checking handle availability…'};
  const handleInvalid=Boolean(formError?.field==='handle' || ['invalid','unavailable'].includes(currentHandle.state));
  const previewHeading=useRef(null), publicationHeading=useRef(null), active=useRef(false);
  useEffect(()=>{
    let current=true; active.current=true;
    request({action:'community'}).then(next=>{if(current){setData(next);if(next.draft){setDraft(editable(next.draft));setPreview(next.draft);}setMessage(next.draft?'Your private draft is loaded. Review the preview before choosing whether to publish.':'');}})
      .catch(error=>{if(current){if(error.status===401)onSignedOut();else setMessage(error.message);}});
    return ()=>{current=false;active.current=false;};
  },[request]);
  useEffect(()=>{
    if(!data)return;
    const handle=draft.handle, sequence=++handleSequence.current;
    if(!handle){setHandleCheck({handle,state:'idle',message:handleHint});return;}
    if(!handleValid(handle)){setHandleCheck({handle,state:'invalid',message:handleHint});return;}
    let current=true;
    setHandleCheck({handle,state:'checking',message:'Checking handle availability…'});
    const timer=window.setTimeout(()=>{
      request({action:'check-community-handle',handle}).then(result=>{
        if(current && sequence===handleSequence.current)setHandleCheck({handle,state:result.available?'available':'unavailable',message:result.reason});
      }).catch(error=>{
        if(!current || sequence!==handleSequence.current)return;
        if(error.status===401)onSignedOut();
        else setHandleCheck({handle,state:'error',message:'Availability could not be checked. Save and preview will check again, or try editing the handle.'});
      });
    },400);
    return ()=>{current=false;window.clearTimeout(timer);};
  },[draft.handle,data,request]);
  useLayoutEffect(()=>{
    if(!formError || busy)return;
    const input=form.current?.elements.namedItem(fieldIds[formError.field]);
    (input || errorSummary.current)?.focus();
  },[formError,busy]);
  useLayoutEffect(()=>{
    if(!data || !focusTarget)return;
    const target=focusTarget==='preview'?previewHeading.current:publicationHeading.current;
    if(target){target.focus();setFocusTarget(null);}
  },[data,preview,focusTarget]);
  function change(key,value){if(key==='handle')handleSequence.current++;setDraft(current=>({...current,[key]:value}));setPreview(null);setConsent(false);setFormError(null);setMessage('');}
  function save(event){
    event.preventDefault();
    if(currentHandle.state==='unavailable'){setFormError({field:'handle',message:currentHandle.message});setMessage('');return;}
    const problem=draftProblem(draft);
    if(problem){setFormError(problem);setMessage('');return;}
    void act({action:'save-community',...draft},'Private draft saved. Review the public preview before publishing.');
  }
  async function act(body,success){
    if(busy)return;setBusy(true);setFormError(null);setMessage('Saving…');setConsent(false);setFocusTarget(null);
    try{
      await request(body);if(!active.current)return;
      // Never leave stale public/preview claims visible after a committed change.
      setData(null);setPreview(null);
      try{
        const next=await request({action:'community'});if(!active.current)return;
        setData(next);setMessage(success);
        if(body.action==='save-community'){setDraft(editable(next.draft));setPreview(next.draft);setFocusTarget('preview');}
        else setFocusTarget('publication');
      }catch(error){if(!active.current)return;if(error.status===401)onSignedOut();else setMessage(`${success} Reload to check the saved details; they could not be refreshed.`);}
    }catch(error){if(!active.current)return;if(error.status===401)onSignedOut();else{setPreview(null);const explanation=error.name==='TimeoutError'?'That took too long. Reload to check the saved state before retrying.':error.message;setMessage('');setFormError({field:error.field,message:explanation});if(error.field==='handle'){handleSequence.current++;setHandleCheck({handle:draft.handle,state:'unavailable',message:explanation});}}}
    finally{if(active.current)setBusy(false);}
  }
  return <>
    <p role="status" className="account-status">{message}</p>
    {!data && <p><a href="/account/community">Reload community profile</a></p>}
    {data && <>
      {!data.communityOpen && <p>Public community profiles are not open right now. You can prepare a private draft or unpublish a saved publication.</p>}
      {data.publicationBlocked && <p>Publication of this profile is paused for moderation. You can still unpublish.</p>}
      <form ref={form} className="account-card" noValidate onSubmit={save}>
        <fieldset disabled={busy}><legend>Public details you choose</legend>
          <label htmlFor="community-handle">Handle (3–30 letters, numbers or hyphens)</label>
          <input id="community-handle" autoCapitalize="none" autoComplete="off" required minLength={3} maxLength={30} pattern={"[a-z0-9][a-z0-9\\-]{1,28}[a-z0-9]"} readOnly={data.handleLocked} aria-describedby="community-handle-help community-handle-status" aria-invalid={handleInvalid || undefined} value={draft.handle} onChange={e=>change('handle',e.target.value.toLowerCase())}/>
          <p id="community-handle-status" role="status">{currentHandle.message}</p>
          <p id="community-handle-help">The handle forms your profile URL. It cannot be renamed after the first publication in this version. Deleting the account releases it for possible reuse.</p>
          <label htmlFor="community-name">Public display name (up to 80 characters)</label>
          <input id="community-name" aria-invalid={formError?.field==='displayName' || undefined} aria-describedby={formError?.field==='displayName'?'community-save-error':undefined} required maxLength={80} value={draft.displayName} onChange={e=>change('displayName',e.target.value)}/>
          <label htmlFor="community-bio">Public bio (optional, up to 500 characters)</label>
          <textarea id="community-bio" aria-invalid={formError?.field==='bio' || undefined} aria-describedby={formError?.field==='bio'?'community-save-error':undefined} rows={4} maxLength={500} value={draft.bio} onChange={e=>change('bio',e.target.value)}/>
          <label htmlFor="community-link">Public website (optional HTTPS link)</label>
          <input id="community-link" aria-invalid={formError?.field==='link' || undefined} aria-describedby={formError?.field==='link'?'community-save-error':undefined} type="url" maxLength={300} value={draft.link} onChange={e=>change('link',e.target.value)}/>
          <p>These details are separate from your private profile. Your account email, beta choices, feedback and Pro interest are not added to this page.</p>
          <p id="community-save-error" ref={errorSummary} role="alert" tabIndex={-1} className="community-save-error">{formError?.message}</p>
          <button type="submit">{busy?'Saving…':'Save and preview'}</button>
        </fieldset>
      </form>
      {preview && <div className="account-card">
        <h2 ref={previewHeading} tabIndex={-1}>Public preview</h2>
        <PublicProfileCard profile={preview}/>
        <p>Profile path: /people/{preview.handle}</p>
        <p>Anyone can view, copy or share published details. Unpublishing removes EXP’s public view; other people may retain copies. Reports may preserve a private copy for moderation.</p>
        <label className="account-check"><input type="checkbox" checked={consent} disabled={busy || !data.communityOpen || data.publicationBlocked} onChange={e=>setConsent(e.target.checked)}/><span>Publish these previewed details publicly.</span></label>
        <button type="button" disabled={busy || !consent || !data.communityOpen || data.publicationBlocked} onClick={()=>act({action:'publish-community',revision:preview.revision,confirmed:true,consentVersion:'community-profile-v1'},'Your community profile is published.')}>Publish community profile</button>
      </div>}
      <div className="account-card">
        <h2 ref={publicationHeading} tabIndex={-1}>Publication status</h2>
        {data.published ? <>
          <p>{data.communityOpen && !data.publicationBlocked?'These saved details are published.':'A publication is saved, but public viewing is currently paused. It may become visible again when the pause ends; unpublish to withdraw it.'}</p>
          <PublicProfileCard profile={data.published}/>
          {data.communityOpen && !data.publicationBlocked && <p><a href={`/people/${data.published.handle}`}>View public profile</a></p>}
          <button type="button" disabled={busy} onClick={()=>act({action:'unpublish-community'},'Your community profile is unpublished. Your private draft is kept.')}>Unpublish community profile</button>
        </> : <p>No community profile is published. Saving or editing a draft does not publish it.</p>}
      </div>
    </>}
  </>;
}
