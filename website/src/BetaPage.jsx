import React, { useEffect, useRef, useState } from 'react';

export default function BetaPage({ request, onSignedOut }) {
  const [data, setData] = useState(null);
  const [participating, setParticipating] = useState(false);
  const [inviteEmails, setInviteEmails] = useState(false);
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const submissionId = useRef(null);
  const mounted = useRef(false);
  const [status, setStatus] = useState('Loading beta choices and feedback…');
  const [busy, setBusy] = useState(false);
  const listHeading = useRef(null);
  const subjectField = useRef(null);

  function receive(next) {
    setData(next); setParticipating(next.participation.participating); setInviteEmails(next.participation.inviteEmails);
  }
  useEffect(() => {
    mounted.current = true;
    let active = true;
    request({ action: 'beta' }).then(next => { if (active) { receive(next); setStatus(''); } })
      .catch(error => { if (active) { if (error.status === 401) onSignedOut(); else setStatus(error.message); } });
    return () => { active = false; mounted.current = false; };
  }, [request]);

  async function act(body, success) {
    if (busy) return;
    setBusy(true); setStatus('Saving…');
    try {
      await request(body);
      if (!mounted.current) return;
      // A committed submission is successful even if refreshing its list fails.
      if (body.action === 'submit-beta-feedback') { setSubject(''); setMessage(''); submissionId.current = null; }
      try {
        const next = await request({ action: 'beta' });
        if (!mounted.current) return;
        receive(next); setStatus(success);
      }
      catch (error) {
        if (!mounted.current) return;
        if (error.status === 401) { onSignedOut(); return; }
        setStatus(`${success} Could not refresh the saved details. Reload this page to check them.`);
      }
      if (body.action === 'delete-beta-feedback') window.requestAnimationFrame(() => listHeading.current?.focus());
      if (body.action === 'submit-beta-feedback') window.requestAnimationFrame(() => subjectField.current?.focus());
    } catch (error) {
      if (!mounted.current) return;
      if (error.status === 401) onSignedOut();
      else setStatus(error.name === 'TimeoutError' ? 'That took too long. Try again with the same feedback to avoid a duplicate.' : error.message);
    } finally { if (mounted.current) setBusy(false); }
  }
  return <>
    <p role="status" className="account-status">{status}</p>
    {!data && <p><a href="/account/beta">Reload beta & feedback</a></p>}
    {data && <>
      {!data.betaOpen && <p>New beta participation and feedback are paused. You can still review your notes, withdraw or delete feedback.</p>}
      <form className="account-card" onSubmit={e => { e.preventDefault(); act({ action: 'save-beta', participating, inviteEmails,
        permissionVersion: 'beta-participation-v1' }, participating ? 'Beta choices saved.' : 'Beta participation and beta invitations are off. Your saved feedback is unchanged.'); }}>
        <fieldset disabled={busy}><legend>Beta participation</legend>
          <label className="account-check"><input type="checkbox" checked={participating} disabled={!data.betaOpen && !participating}
            onChange={e => { setParticipating(e.target.checked); if (!e.target.checked) setInviteEmails(false); }} />
            <span>I’d like to participate in EXP beta testing.</span></label>
          <label className="account-check"><input type="checkbox" checked={inviteEmails} disabled={!participating || (!data.betaOpen && !inviteEmails)} onChange={e => setInviteEmails(e.target.checked)} />
            <span>Email me beta invitations and testing requests at my verified account address.</span></label>
          <p>Your choice is private. It does not guarantee a place in a beta or subscribe you to Pro, news or release emails. Turn participation off to withdraw both choices.</p>
          <p>Feedback is welcome even if you don’t join. Beta invitations are not being sent from this account area yet.</p>
          <button type="submit">Save beta choices</button>
        </fieldset>
      </form>
      <form className="account-card" onSubmit={e => {
        e.preventDefault();
        const id = submissionId.current || crypto.randomUUID(); submissionId.current = id;
        act({ action: 'submit-beta-feedback', id, subject, message }, 'Your private feedback was received.');
      }}>
        <fieldset disabled={busy || !data.betaOpen || data.feedback.length >= 50}><legend>Send private feedback</legend>
          <label htmlFor="beta-subject">Subject (up to 120 characters)</label>
          <input id="beta-subject" ref={subjectField} required maxLength={120} value={subject} onChange={e => { setSubject(e.target.value); submissionId.current = null; }} />
          <label htmlFor="beta-message">What happened, or what would help? (up to 1,500 characters)</label>
          <textarea id="beta-message" rows={5} required maxLength={1500} value={message} onChange={e => { setMessage(e.target.value); submissionId.current = null; }} />
          <p>Visible to you and the EXP developer. Please leave out passwords, client work and other people’s private information. Text only; no file uploads.</p>
          <button type="submit">Send feedback</button>
        </fieldset>
        {data.feedback.length >= 50 && <p>You have 50 saved notes. Delete an old note to add another.</p>}
      </form>
      <div className="account-card">
        <h2 ref={listHeading} tabIndex={-1}>Your saved feedback</h2>
        <p>“Received” means saved, not reviewed or resolved. Replies and progress tracking will come later. You can keep up to 50 notes here.</p>
        {!data.feedback.length && <p>No feedback yet.</p>}
        <ul className="account-feedback-list">{data.feedback.map(note => <li key={note.id}>
          <h3>{note.subject}</h3>
          <p>Received · <time dateTime={note.createdAt}>{new Date(note.createdAt).toLocaleString()}</time></p>
          <p className="account-feedback-message">{note.message}</p>
          <details className="account-delete"><summary>Delete feedback<span className="visually-hidden">: {note.subject}</span></summary>
            <p>Delete this feedback from the live account store? This cannot be undone. Provider logs and backups follow their separate retention.</p>
            <button disabled={busy} type="button" onClick={() => act({ action: 'delete-beta-feedback', id: note.id }, 'Feedback deleted from the live account store.')}>Confirm deletion</button>
          </details>
        </li>)}</ul>
      </div>
    </>}
  </>;
}
