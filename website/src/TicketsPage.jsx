import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';

const receiptFor=(ref,payload)=>{
  const key=JSON.stringify(payload);
  if(ref.current?.key!==key)ref.current={key,id:crypto.randomUUID()};
  return ref.current.id;
};
const date=value=>new Date(value).toLocaleString();
export default function TicketsPage({request,onSignedOut,support=false}) {
  const [list,setList]=useState(null),[thread,setThread]=useState(null),[selected,setSelected]=useState(()=>new URLSearchParams(window.location.search).get('ticket'));
  const [before,setBefore]=useState(undefined),[refresh,setRefresh]=useState(0),[busy,setBusy]=useState(false),[focusThread,setFocusThread]=useState(false);
  const [message,setMessage]=useState('Loading tickets…'),[subject,setSubject]=useState(''),[body,setBody]=useState(''),[reply,setReply]=useState(''),[confirmation,setConfirmation]=useState('');
  const createReceipt=useRef(null),replyReceipt=useRef(null),statusReceipt=useRef(null),heading=useRef(null),listHeading=useRef(null),pendingMessage=useRef(''),alive=useRef(false);
  useEffect(()=>{alive.current=true;return()=>{alive.current=false;};},[]);
  useEffect(()=>{
    let current=true;setList(null);setThread(null);setMessage('Loading tickets…');
    Promise.all([request({action:'tickets',scope:support?'support':'own',...(before?{before}:{})}),selected?request({action:'ticket',id:selected}):Promise.resolve(null)])
      .then(([next,detail])=>{if(current){setList(next);setThread(detail);setMessage(pendingMessage.current);pendingMessage.current='';}})
      .catch(error=>{if(current){if(error.status===401)onSignedOut();else setMessage(pendingMessage.current?`${pendingMessage.current} Refresh tickets to check the saved state.`:error.message);}});
    return()=>{current=false;};
  },[request,support,before,selected,refresh]);
  useLayoutEffect(()=>{if(focusThread && list && (!selected || thread)){(selected?heading:listHeading).current?.focus();setFocusThread(false);}},[thread,list,selected,focusThread]);
  function open(id){setSelected(id);setReply('');setConfirmation('');setFocusThread(true);window.history.replaceState(null,'',`${support?'/account/support':'/account/tickets'}?ticket=${id}`);}
  async function mutate(payload,success){
    if(busy)return;setBusy(true);setMessage('Saving ticket…');
    try{
      const next=await request(payload);if(!alive.current)return;
      setThread(null);setList(null);
      if(payload.action==='create-ticket'){setSubject('');setBody('');createReceipt.current=null;open(next.id);}
      if(payload.action==='reply-ticket'){setReply('');replyReceipt.current=null;setFocusThread(true);}
      if(payload.action==='delete-ticket'){setSelected(null);setConfirmation('');window.history.replaceState(null,'',support?'/account/support':'/account/tickets');}
      pendingMessage.current=success;setBefore(undefined);setFocusThread(true);setRefresh(value=>value+1);
    }catch(error){if(!alive.current)return;if(error.status===401)onSignedOut();else setMessage(error.name==='TimeoutError'?'That took too long. Your draft is kept. Refresh before retrying; the request may have been saved.':error.message);}
    finally{if(alive.current)setBusy(false);}
  }
  function setStatus(status){mutate({action:'set-ticket-status',id:selected,receipt:receiptFor(statusReceipt,{selected,status,revision:thread.ticket.revision}),revision:thread.ticket.revision,status},status==='closed'?'Ticket closed.':'Ticket reopened.');}
  async function setEmailAlerts(emailAlerts){
    if(busy)return;setBusy(true);setMessage('Saving ticket email choice…');
    try{
      const next=await request({action:'save-ticket-preferences',emailAlerts});
      if(alive.current){setList(current=>({...current,ticketEmailsEnabled:next.ticketEmailsEnabled}));setMessage('Ticket email choice saved. News, beta and Pro email choices are unchanged.');}
    }catch(error){if(alive.current){if(error.status===401)onSignedOut();else setMessage(error.message);}}
    finally{if(alive.current)setBusy(false);}
  }
  return <>
    <p role="status" className="account-status">{message}</p>
    <p>Tickets and all replies are private to the ticket author and authorized EXP support staff. Read and respond here; email alerts contain a sign-in link without ticket text.</p>
    {list?.ticketEmailPreferencesAvailable && <>
      <label className="account-check" htmlFor="ticket-email-alerts"><input id="ticket-email-alerts" type="checkbox" checked={list.ticketEmailsEnabled} aria-disabled={busy} onClick={event=>{if(busy)event.preventDefault();}} onChange={e=>setEmailAlerts(e.target.checked)}/> Email me about ticket replies{list.canSupport?' and member tickets':''}</label>
      <p>{list.ticketMailOpen?'Alerts are sent separately from newsletters. Check here even if an email does not arrive.':'Ticket email delivery is paused. Your choice is saved for when it resumes; check here for replies.'}</p>
    </>}
    {list && !list.ticketEmailPreferencesAvailable && <p>Ticket email alerts are not available yet. Check here for replies.</p>}
    <p>Send text only. Please leave out passwords, private client work and other people’s personal details. No files, device logs or design contents are attached automatically.</p>
    {list?.canSupport && <p><a href={support?'/account/tickets':'/account/support'}>{support?'My tickets':'Open support inbox'}</a></p>}
    <button type="button" className="account-secondary" disabled={busy} onClick={()=>setRefresh(value=>value+1)}>Refresh tickets</button>
    {list && !list.ticketsOpen && <p>New tickets and replies are paused. Existing threads remain readable; closing and deleting your own tickets remain available.</p>}
    {thread && <section className="account-card" aria-labelledby="ticket-thread-title">
      <h2 id="ticket-thread-title" tabIndex={-1} ref={heading}>{thread.ticket.subject}</h2>
      <p>Status: <strong>{thread.ticket.status}</strong> · Updated <time dateTime={thread.ticket.updatedAt}>{date(thread.ticket.updatedAt)}</time></p>
      <ol className="account-feedback-list ticket-events">{thread.events.map(event=><li key={event.id}>
        <p><strong>{event.by==='support'?'EXP support':'Ticket author'}</strong> · <time dateTime={event.createdAt}>{date(event.createdAt)}</time></p>
        {['opened','reply'].includes(event.kind)?<p className="account-feedback-message">{event.message}</p>:<p>{event.kind==='closed'?'Closed the ticket.':'Reopened the ticket.'}</p>}
      </li>)}</ol>
      {thread.ticket.status==='open' && thread.ticketsOpen && <form onSubmit={event=>{event.preventDefault();mutate({action:'reply-ticket',id:selected,receipt:receiptFor(replyReceipt,{selected,reply}),revision:thread.ticket.revision,message:reply},'Reply saved.');}}>
        <fieldset disabled={busy}><legend>Reply to this private thread</legend>
          <label htmlFor="ticket-reply">Your reply (up to 1,500 characters)</label><textarea id="ticket-reply" required rows={5} maxLength={1500} value={reply} onChange={e=>{setReply(e.target.value);replyReceipt.current=null;}}/>
          <p>Every reply here is visible to the ticket author and authorized support staff.</p><button type="submit">Send reply</button>
        </fieldset>
      </form>}
      <p><button type="button" className="account-secondary" disabled={busy || (thread.ticket.status==='closed' && !thread.ticketsOpen)} onClick={()=>setStatus(thread.ticket.status==='open'?'closed':'open')}>{thread.ticket.status==='open'?'Close ticket':'Reopen ticket'}</button></p>
      {thread.canDelete && <details className="account-delete"><summary>Delete this ticket</summary>
        <p>This permanently removes the live thread, all replies and its support audit records. Sent mail, provider logs and backups have separate retention.</p>
        <form onSubmit={event=>{event.preventDefault();mutate({action:'delete-ticket',id:selected,confirmation},'Ticket and its replies deleted.');}}><fieldset disabled={busy}>
          <legend>Confirm ticket deletion</legend><label htmlFor="ticket-delete">Type DELETE to remove this ticket</label><input id="ticket-delete" required pattern="DELETE" value={confirmation} onChange={e=>setConfirmation(e.target.value)}/><button type="submit">Delete ticket permanently</button>
        </fieldset></form>
      </details>}
    </section>}
    {list && <div className="account-card"><h2 tabIndex={-1} ref={listHeading}>{support?'Support inbox':'Your tickets'}</h2>
      {!list.tickets.length && <p>No tickets on this page.</p>}
      <ul className="account-feedback-list">{list.tickets.map(ticket=><li key={ticket.id}><button type="button" className="account-secondary ticket-subject" onClick={()=>open(ticket.id)} disabled={busy}>{ticket.subject}</button><p>{ticket.status} · Updated <time dateTime={ticket.updatedAt}>{date(ticket.updatedAt)}</time></p></li>)}</ul>
      <div className="account-session-actions">{before && <button type="button" disabled={busy} onClick={()=>setBefore(undefined)}>Newest tickets</button>}{list.next && <button type="button" disabled={busy} onClick={()=>setBefore(list.next)}>Older tickets</button>}</div>
    </div>}
    {!support && list?.ticketsOpen && <form className="account-card" onSubmit={event=>{event.preventDefault();mutate({action:'create-ticket',id:receiptFor(createReceipt,{subject,body}),subject,message:body},'Ticket received. This is a storage receipt, not a review or response-time promise.');}}>
      <fieldset disabled={busy}><legend>Open a private ticket</legend>
        <label htmlFor="ticket-subject">Subject (up to 120 characters)</label><input id="ticket-subject" required maxLength={120} value={subject} onChange={e=>{setSubject(e.target.value);createReceipt.current=null;}}/>
        <label htmlFor="ticket-message">What can we help with? (up to 1,500 characters)</label><textarea id="ticket-message" required rows={6} maxLength={1500} value={body} onChange={e=>{setBody(e.target.value);createReceipt.current=null;}}/>
        <p>Up to 50 saved tickets per account. Deleting your account removes your authored tickets and all replies. Closed tickets are scheduled for deletion after 180 days without changes once the retention policy is enabled.</p><button type="submit">Open ticket</button>
      </fieldset>
    </form>}
  </>;
}
