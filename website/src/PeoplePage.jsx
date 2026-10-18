import React, { useEffect, useState } from 'react';
import accountRequest from './account-request.js';
import PublicProfileCard from './PublicProfileCard.jsx';
import './account.css';

export default function PeoplePage({ handle }) {
  const [profile,setProfile]=useState(null),[status,setStatus]=useState('Loading community profile…');
  const [category,setCategory]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[sent,setSent]=useState(false);
  useEffect(()=>{
    let active=true;document.title='Community profile — EXP [design]';
    fetch(`/api/people?handle=${encodeURIComponent(handle)}`,{credentials:'omit',cache:'no-store',signal:AbortSignal.timeout(15000)})
      .then(async response=>{const result=await response.json().catch(()=>({}));if(!response.ok || result.ok!==true)throw Error(result.error||'Profile not found.');if(active){setProfile(result.profile);setStatus('');}})
      .catch(error=>{if(active)setStatus(error.name==='TimeoutError'?'That took too long. Please try again later.':error.message);});
    return()=>{active=false;};
  },[handle]);
  async function report(event){
    event.preventDefault();setBusy(true);setStatus('Sending report…');
    try{await accountRequest({action:'report-community',handle,category,reason});setSent(true);setReason('');setStatus('Report received privately for the EXP developer. Receipt does not mean it has been reviewed.');}
    catch(error){setStatus(error.status===401?'Please sign in to your free account, then return here to send the report.':error.name==='TimeoutError'?'That took too long. You can retry the same report.':error.message);}
    finally{setBusy(false);}
  }
  return <section className="account-page" aria-labelledby="people-title">
    <p className="section-label">EXP community</p><h1 id="people-title">Community profile.</h1>
    <p role="status" className="account-status">{status}</p>
    {profile && <>
      <div className="account-card"><PublicProfileCard profile={profile}/></div>
      <details className="account-card account-delete"><summary>Report this profile</summary>
        <p>Reports require a <a href="/account">signed-in free account</a>. Reports and your account identity are private to the EXP developer. Please leave out passwords and other people’s private details.</p>
        <form onSubmit={report}><fieldset disabled={busy || sent}><legend>Private profile report</legend>
          <label htmlFor="report-category">Reason category</label><select id="report-category" required value={category} onChange={e=>setCategory(e.target.value)}>
            <option value="">Choose a category</option><option value="spam">Spam</option><option value="harassment">Harassment</option><option value="privacy">Privacy</option><option value="other">Other</option>
          </select>
          <label htmlFor="report-reason">What should we review? (up to 500 characters)</label><textarea id="report-reason" required rows={4} maxLength={500} value={reason} onChange={e=>setReason(e.target.value)}/>
          <p>You can report each published version once; repeated submissions keep the first report for that version. A private copy of the published details is kept for moderation. Reports are removed when the reporting or reported account is deleted; provider logs and backups have separate retention.</p>
          <button type="submit">Send private report</button>
        </fieldset></form>
      </details>
    </>}
    <p><a href="/account/community">Manage your community profile</a></p>
  </section>;
}
