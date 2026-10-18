import React, { useEffect, useState } from 'react';

export default function NewsPreferences({request,onSignedOut}) {
  const [data,setData]=useState(null),[choice,setChoice]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('Loading development-news preference…');
  useEffect(()=>{
    let active=true;
    request({action:'news-preference'}).then(next=>{if(active){setData(next);setChoice(next.enabled);setMessage('');}})
      .catch(error=>{if(active){if(error.status===401)onSignedOut();else setMessage(error.message);}});
    return()=>{active=false;};
  },[request]);
  async function save(event){
    event.preventDefault();if(busy)return;setBusy(true);setMessage('Saving news permission…');
    try{const next=await request({action:'save-news-preference',enabled:choice,permissionVersion:'development-news-v1'});setData(next);setChoice(next.enabled);setMessage(next.enabled?'Development-news permission saved. Email delivery is not active yet.':'Development-news email permission is off.');}
    catch(error){if(error.status===401)onSignedOut();else setMessage(error.name==='TimeoutError'?'That took too long. Reload to check your saved permission.':error.message);}
    finally{setBusy(false);}
  }
  return <div className="account-card">
    <h2>Development news by email</h2><p role="status" className="account-status">{message}</p>
    <p><a href="/news">Read news and updates</a> without email or an account. This choice is separate from release-list, beta and Pro permissions.</p>
    {data && <form onSubmit={save}><fieldset disabled={busy}>
      <legend>Optional development-news permission</legend>
      {!data.newsOpen && <p>New permissions are paused. You can still turn off a saved choice.</p>}
      <label className="account-check"><input type="checkbox" checked={choice} disabled={!data.newsOpen && !data.enabled} onChange={e=>setChoice(e.target.checked)}/><span>Email me occasional EXP development news at my verified account address. I can turn this off here anytime.</span></label>
      <p>Email delivery is not active yet. Saving permission does not send mail or enroll you in any other list.</p>
      <button type="submit">Save news permission</button>
    </fieldset></form>}
  </div>;
}
