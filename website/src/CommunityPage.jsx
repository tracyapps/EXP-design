import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import PublicProfileCard from './PublicProfileCard.jsx';

const blank = { handle:'', displayName:'', bio:'', link:'' };
const editable = value => ({handle:value.handle,displayName:value.displayName,bio:value.bio,link:value.link});
export default function CommunityPage({ request, onSignedOut }) {
  const [data,setData]=useState(null), [draft,setDraft]=useState(blank), [preview,setPreview]=useState(null);
  const [consent,setConsent]=useState(false), [busy,setBusy]=useState(false), [message,setMessage]=useState('Loading community profile…');
  const [focusTarget,setFocusTarget]=useState(null);
  const previewHeading=useRef(null), publicationHeading=useRef(null), active=useRef(false);
  useEffect(()=>{
    let current=true; active.current=true;
    request({action:'community'}).then(next=>{if(current){setData(next);if(next.draft)setDraft(editable(next.draft));setMessage('');}})
      .catch(error=>{if(current){if(error.status===401)onSignedOut();else setMessage(error.message);}});
    return ()=>{current=false;active.current=false;};
  },[request]);
  useLayoutEffect(()=>{
    if(!data || !focusTarget)return;
    const target=focusTarget==='preview'?previewHeading.current:publicationHeading.current;
    if(target){target.focus();setFocusTarget(null);}
  },[data,preview,focusTarget]);
  function change(key,value){setDraft({...draft,[key]:value});setPreview(null);setConsent(false);}
  async function act(body,success){
    if(busy)return;setBusy(true);setMessage('Saving…');setConsent(false);setFocusTarget(null);
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
    }catch(error){if(!active.current)return;if(error.status===401)onSignedOut();else{setPreview(null);setMessage(error.name==='TimeoutError'?'That took too long. Reload to check the saved state before retrying.':error.message);}}
    finally{if(active.current)setBusy(false);}
  }
  return <>
    <p role="status" className="account-status">{message}</p>
    {!data && <p><a href="/account/community">Reload community profile</a></p>}
    {data && <>
      {!data.communityOpen && <p>Public community profiles are not open right now. You can prepare a private draft or unpublish a saved publication.</p>}
      {data.publicationBlocked && <p>Publication of this profile is paused for moderation. You can still unpublish.</p>}
      <form className="account-card" onSubmit={e=>{e.preventDefault();act({action:'save-community',...draft},'Private draft saved. Review the public preview before publishing.');}}>
        <fieldset disabled={busy}><legend>Public details you choose</legend>
          <label htmlFor="community-handle">Handle (3–30 letters, numbers or hyphens)</label>
          <input id="community-handle" autoCapitalize="none" autoComplete="off" required minLength={3} maxLength={30} pattern={"[a-z0-9][a-z0-9\\-]{1,28}[a-z0-9]"} readOnly={data.handleLocked} value={draft.handle} onChange={e=>change('handle',e.target.value.toLowerCase())}/>
          <p>The handle forms your profile URL. It cannot be renamed after the first publication in this version. Deleting the account releases it for possible reuse.</p>
          <label htmlFor="community-name">Public display name (up to 80 characters)</label>
          <input id="community-name" required maxLength={80} value={draft.displayName} onChange={e=>change('displayName',e.target.value)}/>
          <label htmlFor="community-bio">Public bio (optional, up to 500 characters)</label>
          <textarea id="community-bio" rows={4} maxLength={500} value={draft.bio} onChange={e=>change('bio',e.target.value)}/>
          <label htmlFor="community-link">Public website (optional HTTPS link)</label>
          <input id="community-link" type="url" maxLength={300} value={draft.link} onChange={e=>change('link',e.target.value)}/>
          <p>These details are separate from your private profile. Your account email, beta choices, feedback and Pro interest are not added to this page.</p>
          <button type="submit">Save and preview</button>
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
