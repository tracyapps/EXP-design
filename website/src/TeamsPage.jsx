import React, { useEffect, useRef, useState } from 'react';
import { options } from '../../server/teams/schema.js';
import './interest.css';
import './teams.css';

const validToken = token => /^[A-Za-z0-9_-]{43}$/.test(token);
function newToken() {
  return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
}
async function post(operation,token,body={}) {
  const response=await fetch('/api/team-research',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({operation,token,...body}),signal:AbortSignal.timeout(15000)});
  const result=await response.json().catch(()=>({}));
  if (!response.ok || result.ok!==true) throw new Error(result.error || 'that didn’t go through. your answers are still here—please try again.');
  return result;
}
function Select({name,label,value,onChange}) {
  return <div className="team-field"><label htmlFor={`team-${name}`}>{label}</label>
    <select id={`team-${name}`} value={value} onChange={e=>onChange(name,e.target.value)}>
      <option value="">choose one, or skip this</option>
      {options[name].map(option=><option key={option}>{option}</option>)}
    </select></div>;
}
function Choices({name,label,value,onChange}) {
  function toggle(option,checked) {
    const next=checked ? option==='not sure' ? ['not sure'] : [...value.filter(item=>item!=='not sure'),option] : value.filter(item=>item!==option);
    onChange(name,next);
  }
  return <fieldset className="team-choices"><legend>{label}</legend>{options[name].map(option=>
    <label key={option}><input type="checkbox" checked={value.includes(option)} onChange={e=>toggle(option,e.target.checked)}/>{option}</label>)}</fieldset>;
}
function FollowUp({token,disabled}) {
  const [email,setEmail]=useState(''),[consent,setConsent]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
  async function submit(e) {
    e.preventDefault();setBusy(true);setMessage('sending the confirmation…');
    try {await post('contact',token,{email,consent,consentVersion:'team-research-contact-v1'});
      setMessage('check your inbox. confirm there if you want to hear from me. already confirmed? you’re all set. if you just requested a link, give it 10 minutes before trying again.');}
    catch(error){setMessage(error.message);}finally{setBusy(false);}
  }
  return <form className="interest-form team-followup" onSubmit={submit}>
    <h2>up for a follow-up?</h2>
    <p>optional, actually. your answers are already saved. if you’d like to talk through them, leave an email and confirm the link i send.</p>
    <label htmlFor="team-email">email</label><input id="team-email" type="email" autoComplete="email" required maxLength={254} value={email} onChange={e=>setEmail(e.target.value)} disabled={busy || disabled}/>
    <label className="team-check"><input type="checkbox" required checked={consent} onChange={e=>setConsent(e.target.checked)} disabled={busy || disabled}/>
      tracy may email me about my team-research response and invite me to a research conversation.</label>
    <p className="interest-hint">this doesn’t sign you up for a newsletter, Pro updates, or an EXP account. the confirmation email includes a link to stop follow-up or delete your response.</p>
    <button className="interest-button" disabled={busy || disabled}>{busy?'sending…':'email me a confirmation'}</button>
    <p role="status">{message}</p>
  </form>;
}
export default function TeamsPage({mode='survey'}) {
  const [token]=useState(()=>mode==='survey'?newToken():window.location.hash.slice(1));
  const [answers,setAnswers]=useState({role:'',size:'',problem:'',systems:[],tools:[],barrier:'',stack:'',approval:''});
  const [website,setWebsite]=useState(''),[saved,setSaved]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
  const [availability,setAvailability]=useState(null),[deleted,setDeleted]=useState(false),[confirmDone,setConfirmDone]=useState(false);
  const successHeading=useRef(null);
  useEffect(()=>{
    document.title=mode==='survey'?'your team’s workflow (the real one) — EXP [design]':'your team-research response — EXP [design]';
    if(mode!=='survey') window.history.replaceState(null,'',window.location.pathname);
    const controller=new AbortController();
    fetch('/api/team-research',{signal:controller.signal}).then(r=>{if(!r.ok)throw new Error();return r.json();})
      .then(result=>setAvailability(result.ok===true?result:{collecting:false,contact:false}))
      .catch(error=>{if(error.name!=='AbortError')setAvailability({collecting:false,contact:false});});
    return ()=>controller.abort();
  },[mode]);
  useEffect(()=>{if(saved)successHeading.current?.focus();},[saved]);
  const update=(name,value)=>setAnswers(previous=>({...previous,[name]:value}));
  async function save(event) {
    event.preventDefault();setBusy(true);setMessage('saving…');
    try {const result=await post('save',token,{answers,website});setSaved(true);setMessage(result.state==='already_saved' ? 'an earlier attempt already saved your response. changes made after that attempt were not saved. you can delete it using the private link below and start again.' : 'your response is saved. thank you. :)');}
    catch(error){setMessage(error.message);}finally{setBusy(false);}
  }
  async function act(operation) {
    setBusy(true);setMessage('one moment…');
    try {await post(operation,token);
      if(operation==='erase'){setDeleted(true);setMessage('your response and any follow-up email have been deleted from the live research database.');}
      else if(operation==='withdraw')setMessage('follow-up stopped. your email has been removed from the live research record; your survey answers stay.');
      else {setConfirmDone(true);setMessage('confirmed. i can follow up about your response now. thanks for being up for it. :)');}
    }catch(error){setMessage(error.message);}finally{setBusy(false);}
  }
  const manageLink=`${window.location.origin}/teams/manage#${token}`;
  const ready=availability?.collecting===true;
  if(mode!=='survey') return <section className="interest-page interest-action teams-page">
    <p className="section-label">EXP · team research</p><h1>{mode==='confirm'?'one quick check.':'your response. your call.'}</h1>
    {mode==='confirm'?<><p>confirm that tracy can email you about your response and invite you to a research conversation. this doesn’t join any mailing lists.</p>
      <button className="interest-button" disabled={busy || confirmDone || !validToken(token) || !ready} onClick={()=>act('confirm')}>yes, you can follow up</button>
      {!ready && availability && <p>new confirmations are paused right now. the private response link in your email still lets you stop follow-up or delete your response.</p>}</>:
      <><p>stop research follow-up and remove your email, or delete the whole response. neither changes any other EXP signup.</p>
      <div className="team-actions"><button className="interest-button" disabled={busy || deleted || !validToken(token)} onClick={()=>act('withdraw')}>stop follow-up</button>
      <button className="interest-button" disabled={busy || deleted || !validToken(token)} onClick={()=>act('erase')}>delete my response</button></div>
      <p className="interest-hint">deletion removes the live research record. copies already in email, provider logs, or backups follow those services’ retention settings.</p></>}
    {!validToken(token)&&<p>open the complete private link you saved or received by email. reloading this page removes the key from memory; reopen the original link to use it again.</p>}
    <p role="status">{message}</p>
    {mode==='manage' && validToken(token) && !deleted && availability?.contact && <FollowUp token={token} disabled={busy}/>}
    <a href="/teams">back to team research</a>
  </section>;
  return <section className="interest-page teams-page" aria-labelledby="team-title">
    <div className="interest-intro">
      <p className="section-label">EXP for teams · figuring it out</p>
      <h1 id="team-title">how does your team actually work?</h1>
      <p className="interest-lead">the component library. the code. the spreadsheet somebody made because the other two don’t agree.</p>
      <p>i’m exploring a team version of EXP [design]. i have opinions. many of them. but it’s been a while since i worked inside a corporate design team, and i’d rather ask than build around my own outdated assumptions.</p>
      <p>so: what’s annoying? what tools have to stay? and what would it take to get a new one approved?</p>
      <p>answer whatever you know. skip whatever you don’t. there’s no account to create, and nothing to buy here.</p>
      <p className="team-aside">“we have three libraries and nobody knows which one is current” is a perfectly useful answer.</p>
      <a className="interest-text-link" href="/download">just looking for the app? it’s over here.</a>
    </div>
    <div className="team-panel">
      {!saved ? <form className="interest-form glass-thick glass-edge" onSubmit={save}>
        <h2>the short version</h2><p>all questions are optional. one answer is enough to send.</p>
        {availability && !ready && <p role="status">the survey isn’t accepting responses right now. you can read the questions, but sending is paused.</p>}
        <fieldset className="team-fields" disabled={busy}>
          <legend className="team-group-title">a little context</legend>
          <Select name="role" label="what’s your part in all this?" value={answers.role} onChange={update}/>
          <Select name="size" label="roughly how many people work on design + development?" value={answers.size} onChange={update}/>
          <div className="team-field"><label htmlFor="team-problem">what keeps making this harder than it needs to be?</label>
          <p id="team-problem-hint" className="interest-hint">a recent example helps. “nothing, honestly” is also an answer.</p>
          <textarea id="team-problem" rows={4} maxLength={1500} aria-describedby="team-problem-hint" value={answers.problem} onChange={e=>update('problem',e.target.value)}/></div>
          <Choices name="systems" label="what computers does the team use?" value={answers.systems} onChange={update}/>
          <Choices name="tools" label="what would EXP need to work with?" value={answers.tools} onChange={update}/>
          <Select name="barrier" label="what’s most likely to stop you trying a new tool?" value={answers.barrier} onChange={update}/>
          <details className="team-details"><summary>know the technical bits? (optional)</summary>
            <div className="team-field"><label htmlFor="team-stack">which tools, languages, or frameworks?</label><p id="team-stack-hint" className="interest-hint">React, Angular, TypeScript, Storybook, tokens, your own system… names and versions if you know them. no need to go find out.</p>
            <textarea id="team-stack" rows={3} maxLength={1000} aria-describedby="team-stack-hint" value={answers.stack} onChange={e=>update('stack',e.target.value)}/></div>
            <div className="team-field"><label htmlFor="team-approval">what would IT, security, or whoever approves software need?</label><p id="team-approval-hint" className="interest-hint">for example: SSO, local files, no AI, an accessibility review. a rough idea is fine. please don’t paste internal policies or anything confidential.</p>
            <textarea id="team-approval" rows={3} maxLength={1000} aria-describedby="team-approval-hint" value={answers.approval} onChange={e=>update('approval',e.target.value)}/></div>
          </details>
        </fieldset>
        <label className="signup-trap" htmlFor="team-website">website</label><input className="signup-trap" id="team-website" tabIndex={-1} autoComplete="off" value={website} onChange={e=>setWebsite(e.target.value)}/>
        <p className="interest-hint">please leave out client names and confidential details. <a href="#team-privacy">what happens to your answers</a></p>
        <button className="interest-button" disabled={busy || !ready}>{busy?'saving…':availability?'send my answers':'checking availability…'}</button>
        <p className="interest-message" role="status">{message}</p>
      </form> : <div className="interest-form glass-thick glass-edge">
        <h2 tabIndex={-1} ref={successHeading}>this helps. thank you. :)</h2>
        <p role="status">{message}</p>
        <p>i’ll use your answers to work out what a team version needs to do—and whether it’s worth building.</p>
        <label htmlFor="team-private-link">save this private link to delete your response or change follow-up permission later</label>
        <input id="team-private-link" readOnly value={manageLink} onFocus={e=>e.target.select()}/>
        <p className="interest-hint">keep it somewhere safe. anyone with this link can manage this response. we don’t save it in your browser.</p>
        <a href={manageLink}>manage this response</a>
        {availability?.contact && <FollowUp token={token}/>}
        {!availability?.contact && <p>email follow-up isn’t available right now. your answers still count.</p>}
      </div>}
      <aside id="team-privacy" className="team-privacy">
        <h2>what happens to your answers</h2>
        <p>tracy uses these responses to plan EXP for teams. they aren’t published as testimonials or added to mailing lists. no account or email is needed to answer.</p>
        <p>if you separately ask for follow-up, your email is linked to this response. permission starts only after you confirm it by email. you can stop follow-up or delete the response using your private link.</p>
        <p>research records expire after 90 days and are removed by the daily cleanup. unconfirmed email addresses are cleared after their 24-hour confirmation expires. hosting logs, sent email, and backups have their own retention settings. please don’t include confidential information.</p>
      </aside>
    </div>
  </section>;
}
