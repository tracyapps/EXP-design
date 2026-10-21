import React, { useEffect, useRef, useState } from 'react';
import ShareTools from './ShareTools.jsx';
import './engagement.css';

export default function AccountEngagement({ request, onSignedOut, user, view = 'feedback' }) {
  const [data, setData] = useState(null), [status, setStatus] = useState('Loading your private account tools…'), [busy, setBusy] = useState(false);
  const [kind, setKind] = useState('feedback'), [subject, setSubject] = useState(''), [message, setMessage] = useState('');
  const [testimonial, setTestimonial] = useState(false), [firstName, setFirstName] = useState(''), [lastInitial, setLastInitial] = useState('');
  const submission = useRef(null), alive = useRef(false), heading = useRef(null);
  const attribution = firstName.trim() && lastInitial.trim() ? `${firstName.trim()} ${lastInitial.trim().toLocaleUpperCase()}.` : 'your first name + last initial';
  async function refresh() { const next = await request({ action: 'engagement' }); if (alive.current) setData(next); }
  useEffect(() => { alive.current = true; refresh().then(() => { if (alive.current) setStatus(''); }).catch(error => { if (alive.current) { if (error.status === 401) onSignedOut(); else setStatus(error.message); } }); return () => { alive.current = false; }; }, []);
  async function act(body, success) {
    setBusy(true);
    try { await request(body); if (!alive.current) return; await refresh(); if (!alive.current) return;
      setStatus(success);
      if (body.action === 'submit-member-feedback') { setSubject(''); setMessage(''); setTestimonial(false); setFirstName(''); setLastInitial(''); submission.current = null; }
      window.requestAnimationFrame(() => heading.current?.focus());
    } catch (error) { if (alive.current) { if (error.status === 401) onSignedOut(); else setStatus(error.message); } }
    finally { if (alive.current) setBusy(false); }
  }
  return <>
    <p className="account-status" role="status">{status}</p>
    {!data && <p><a href={`/account/${view}`}>Reload {view === 'share' ? 'sharing' : 'feedback'}</a></p>}
    {data && !data.enabled && <p>New feedback, sharing records and signup credit are not open right now. Existing records and withdrawal controls remain available below.</p>}
    {data && view === 'feedback' && <>
      <form className="account-card" onSubmit={event => { event.preventDefault(); const id = submission.current || crypto.randomUUID(); submission.current = id;
        void act({ action: 'submit-member-feedback', id, kind, subject, message, testimonial,
          ...(testimonial ? { firstName, lastInitial, consentVersion: 'testimonial-v1' } : {}) }, 'Your private note was saved. Thank you for helping shape EXP.'); }}>
        <fieldset disabled={busy || !data.enabled || data.feedback.length >= 50}><legend>Tell me what would help.</legend>
          <p>You don’t need to be a beta tester. Share an idea, request a feature, or tell me how EXP fits your work. For a problem that needs a reply, <a href="/account/tickets">open a support ticket</a>.</p>
          <label htmlFor="member-feedback-kind">What are you sending?</label>
          <select id="member-feedback-kind" value={kind} onChange={e => { setKind(e.target.value); submission.current = null; }}><option value="feedback">General feedback</option><option value="feature">Feature request</option></select>
          <label htmlFor="member-feedback-subject">Subject (up to 120 characters)</label><input id="member-feedback-subject" required maxLength={120} value={subject} onChange={e => { setSubject(e.target.value); submission.current = null; }} />
          <label htmlFor="member-feedback-message">What would you like me to know? (up to 1,500 characters)</label><textarea id="member-feedback-message" required rows={6} maxLength={1500} value={message} onChange={e => { setMessage(e.target.value); submission.current = null; }} />
          <p>Private between you and the EXP developer. Please leave out client work, passwords and other people’s private information.</p>
          <label className="engagement-check"><input type="checkbox" checked={testimonial} onChange={e => { setTestimonial(e.target.checked); submission.current = null; }} />Optional: EXP may quote this feedback as a testimonial on its website or marketing materials, credited only with the name I preview below. This does not subscribe me to email or make my profile public.</label>
          {testimonial && <><div className="engagement-attribution"><label htmlFor="testimonial-first">First name<input id="testimonial-first" required maxLength={60} value={firstName} onChange={e => { setFirstName(e.target.value); submission.current = null; }} autoComplete="given-name" /></label>
            <label htmlFor="testimonial-initial">Last initial<input id="testimonial-initial" required maxLength={2} value={lastInitial} onChange={e => { setLastInitial(e.target.value); submission.current = null; }} /></label></div>
            <p className="engagement-preview">Attribution preview: <strong>{attribution}</strong>. Nothing is published automatically.</p></>}
          <p>You can withdraw testimonial permission or delete the note here. Withdrawal stops future reuse; already distributed materials may remain, and website quotes need a manual removal request through support.</p>
          <button type="submit">Send {kind === 'feature' ? 'feature request' : 'feedback'}</button>
        </fieldset>
      </form>
      <div className="account-card"><h2 ref={heading} tabIndex={-1}>Your saved feedback and ideas</h2><p>Received means saved, not promised, reviewed or scheduled. Up to 50 private notes; there are no public votes or automatic testimonials.</p>
        {!data.feedback.length && <p>No notes yet. What would make EXP more useful to you?</p>}
        <ul className="account-feedback-list">{data.feedback.map(note => <li key={note.id}><h3>{note.subject}</h3><p>{note.kind === 'feature' ? 'Feature request' : 'Feedback'} · <time dateTime={note.createdAt}>{new Date(note.createdAt).toLocaleDateString()}</time></p>
          <p className="account-feedback-message">{note.message}</p><p>{note.testimonial ? `Testimonial permission granted as ${note.attribution}` : 'Private feedback. No current testimonial permission.'}</p>
          {note.testimonial && <button type="button" disabled={busy} onClick={() => act({ action: 'withdraw-testimonial', id: note.id }, 'Testimonial permission withdrawn. Future reuse is no longer permitted; contact support about any existing published copy.')}>Withdraw testimonial permission</button>}
          <details className="account-delete"><summary>Delete note<span className="visually-hidden">: {note.subject}</span></summary><p>This deletes the note and permission from the live account store. Logs/backups follow their separate retention. Contact support about already published quotes.</p>
            <button type="button" disabled={busy} onClick={() => act({ action: 'delete-member-feedback', id: note.id }, 'Private note and permission deleted from the live store.')}>Confirm deletion</button></details>
        </li>)}</ul>
      </div>
    </>}
    {data && view === 'share' && <>
      <div className="account-card"><h2 ref={heading} tabIndex={-1}>A little word of mouth goes a long way.</h2><p>Your personal link lets a new member optionally credit you after confirming their account. No referral benefits, rewards or purchase credits are offered or promised.</p>
        <div className="engagement-stats"><p><strong>{data.shareActions}</strong>recorded share actions</p><p><strong>{data.creditedSignups}</strong>active, consented signup credits</p></div>
        <p>Share actions record copying a link or opening/completing a share tool. They do not prove delivery, a public post, unique people or sales. Signup credits can decrease when members withdraw or accounts are deleted.</p>
        <details className="account-delete"><summary>Clear share-action history</summary><p>This clears your action records, not your link or other members’ chosen credit.</p><button disabled={busy} type="button" onClick={() => act({ action: 'clear-member-shares' }, 'Share-action history cleared.')}>Confirm clear history</button></details>
        {data.referral && <div><p>{data.referral.active ? 'You chose to credit the member who shared EXP with you.' : 'You have no active signup credit. A withdrawn credit cannot be reassigned.'}</p>
          {data.referral.active && <button disabled={busy} type="button" onClick={() => act({ action: 'withdraw-referral-credit' }, 'Your optional signup credit has been withdrawn.')}>Withdraw my signup credit</button>}</div>}
      </div>
      <ShareTools memberData={data} onChanged={refresh} />
    </>}
  </>;
}
