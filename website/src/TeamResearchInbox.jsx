import React, { useEffect, useRef, useState } from 'react';
import './team-inbox.css';

const fields = [
  ['role', 'role'], ['size', 'team size'], ['problem', 'what’s getting in the way'],
  ['systems', 'computers'], ['tools', 'tools that need to stay'], ['barrier', 'biggest adoption barrier'],
  ['stack', 'languages, frameworks + tools'], ['approval', 'approval requirements'],
];
const date = value => new Date(value).toLocaleDateString(undefined, {year:'numeric',month:'short',day:'numeric'});
export function ResearchResponse({response}) {
  return <article className="account-card team-response">
    <h3>response {response.id}</h3>
    <p className="team-response-meta">received <time dateTime={response.createdAt}>{date(response.createdAt)}</time> · expires {date(response.expiresAt)}</p>
    <p>{response.contactState==='confirmed' && response.followupEmail
      ? <>follow-up confirmed: <strong>{response.followupEmail}</strong></>
      : response.contactState==='pending' ? 'follow-up requested, but not confirmed yet. no contact permission.' : 'no follow-up permission. the answers are still useful.'}</p>
    {response.notificationFailed && <p>the notification email couldn’t be delivered after several attempts. this response is still saved here.</p>}
    <dl>{fields.map(([key,label])=>{
      const value=response.answers[key];const text=Array.isArray(value)?value.join(', '):value;
      return text ? <div key={key}><dt>{label}</dt><dd>{text}</dd></div> : null;
    })}</dl>
  </article>;
}
export default function TeamResearchInbox({request,onSignedOut}) {
  const [responses,setResponses]=useState([]),[nextBefore,setNextBefore]=useState(null);
  const [busy,setBusy]=useState(false),[message,setMessage]=useState(''),[loaded,setLoaded]=useState(false);
  const generation=useRef(0),mounted=useRef(false);
  async function load(before=null) {
    const version=++generation.current;
    setBusy(true);setMessage('checking the inbox…');
    if(!before){setResponses([]);setNextBefore(null);setLoaded(false);}
    try {
      const result=await request({action:'team-research-responses',...(before?{before}:{})});
      if(!mounted.current || generation.current!==version)return;
      setResponses(previous=>before?[...previous,...result.responses]:result.responses);
      setNextBefore(result.nextBefore);setLoaded(true);setMessage('up to date.');
    }catch(error){
      if(!mounted.current || generation.current!==version)return;
      setResponses([]);setNextBefore(null);setLoaded(false);setMessage(error.message);
      if(error.status===401)onSignedOut();
    }finally{if(mounted.current && generation.current===version)setBusy(false);}
  }
  useEffect(()=>{mounted.current=true;load();return()=>{mounted.current=false;generation.current++;};},[]);
  return <div className="team-inbox">
    <div className="account-card">
      <h2>what people are telling us</h2>
      <p>newest first. this inbox is private to your account. responses disappear here when they’re deleted or expire.</p>
      <p>refresh before contacting someone: they may have withdrawn follow-up permission since you opened the page.</p>
      <button type="button" disabled={busy} onClick={()=>load()}>refresh responses</button>
      <p role="status">{message}</p>
      {loaded && responses.length===0 && <p>nothing here yet. when someone sends the team survey, this is where it’ll land.</p>}
    </div>
    {responses.map(response=><ResearchResponse key={response.id} response={response}/>)}
    {nextBefore && <button type="button" disabled={busy} onClick={()=>load(nextBefore)}>load older responses</button>}
  </div>;
}
