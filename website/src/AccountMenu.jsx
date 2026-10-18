import React,{useEffect,useId,useRef,useState} from 'react';
import {useAccountSession} from './AccountSession.jsx';
import accountRequest from './account-request.js';
import './account-menu.css';

export function avatarInitials(user) {
  const words=user?.name?.trim().split(/\s+/u)??[];
  return [words[0],words.length>1?words.at(-1):null].filter(Boolean).map(word=>Array.from(word)[0]).join('').toLocaleUpperCase();
}
export function Avatar({user,className=''}) {
  const initials=avatarInitials(user);
  return <span className={`account-avatar ${className}`} aria-hidden="true">{user?.avatar
    ?<img src={user.avatar} alt=""/>
    :initials || <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="8" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/></svg>}</span>;
}
export default function AccountMenu() {
  const session=useAccountSession(),{user}=session;
  const [open,setOpen]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
  const root=useRef(null),trigger=useRef(null),id=useId();
  useEffect(()=>{setOpen(false);if(open)trigger.current?.focus();},[user?.id]);
  useEffect(()=>{
    if(!open)return;
    const outside=event=>{if(root.current && !root.current.contains(event.target))setOpen(false);};
    document.addEventListener('pointerdown',outside);return()=>document.removeEventListener('pointerdown',outside);
  },[open]);
  async function signOut(){
    if(busy)return;setBusy(true);setMessage('Signing out…');
    try{await accountRequest({action:'sign-out'});session.clear();setOpen(false);setMessage('Signed out.');trigger.current?.focus();}
    catch(error){setMessage(error.message);}finally{setBusy(false);}
  }
  return <div ref={root} className="account-header" onBlur={event=>{if(!event.currentTarget.contains(event.relatedTarget))setOpen(false);}}
    onKeyDown={event=>{if(event.key==='Escape' && open){event.preventDefault();setOpen(false);trigger.current?.focus();}}}>
    <button type="button" ref={trigger} className="account-avatar-button" aria-label={user?`${user.avatar?'':`${avatarInitials(user)}: `}Account menu for ${user.name}`:'Sign in or create an EXP account'}
      aria-expanded={open} aria-controls={id} onClick={()=>setOpen(value=>!value)}><Avatar user={user}/></button>
    <div id={id} className={`account-popover${user?.largeText?' account-popover-large':''}`} hidden={!open}>
      {user?<>
        <p className="account-menu-name">{user.name}</p>
        <a href="/account">Account overview</a><a href="/account/profile">Private profile</a><a href="/account/preferences">Preferences</a>
        <a href="/account/beta">Beta &amp; feedback</a><a href="/account/pro">Pro interest</a><a href="/account/community">Community profile</a>
        <a href="/account/tickets">My tickets</a>
      </>:<>
        <p className="account-menu-name">Your free EXP account</p>
        <a href="/account">Sign in</a><a href="/account?intent=register">Create account</a>
        {session.ready && !session.available && <p>Account service is unavailable right now. You can still browse and download EXP.</p>}
      </>}
      <a href="/accounts">About free accounts</a><a href="/news">News &amp; updates</a><a href="/download">Download EXP</a>
      {user && <button type="button" disabled={busy} onClick={signOut}>Sign out</button>}
    </div>
    <span className="account-menu-status" role="status">{message}</span>
  </div>;
}
