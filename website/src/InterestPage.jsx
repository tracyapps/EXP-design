import React, { useEffect, useState } from 'react';
import './interest.css';

const permission = 'Email me about the proposed EXP Pro offer and invite me to give feedback.';

async function post(path, body) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body), signal: controller.signal });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || result.ok !== true) throw new Error(result.error || 'Something went wrong. Please try again.');
    return result;
  } finally { window.clearTimeout(timeout); }
}

export default function InterestPage({ mode = 'request' }) {
  const [token] = useState(() => window.location.hash.slice(1));
  const [email, setEmail] = useState('');
  const [model, setModel] = useState('');
  const [consent, setConsent] = useState(false);
  const [website, setWebsite] = useState('');
  const [status, setStatus] = useState('idle');
  const [message, setMessage] = useState('');
  const [erasureStatus, setErasureStatus] = useState('idle');
  const [erasureMessage, setErasureMessage] = useState('');
  const busy = status === 'submitting';
  const done = status === 'success';
  const hasToken = /^[A-Za-z0-9_-]{43}$/.test(token);
  const withdrawing = mode === 'withdraw';
  const deleting = mode === 'erase';

  useEffect(() => {
    document.title = mode === 'request' ? 'Help shape EXP Pro — EXP [design]' :
      `${deleting ? 'Delete' : withdrawing ? 'Withdraw' : 'Confirm'} Pro interest — EXP [design]`;
    if (mode !== 'request') {
      // Keep the capability in component memory only. No cookies/localStorage;
      // reopening the original email link restores it after a reload.
      window.history.replaceState(null, '', window.location.pathname);
    }
  }, [mode, withdrawing, deleting]);

  async function submit(event) {
    event.preventDefault();
    setStatus('submitting'); setMessage('Sending…');
    try {
      if (mode === 'request') {
        const result = await post('/api/pro-interest', { email, model, consent, website,
          source: 'pro page', consentVersion: 'pro-interest-v1' });
        if (result.state !== 'pending') throw new Error('Could not verify the request. Please try again.');
        setMessage("Check your inbox for a confirmation link. If you already confirmed, you're all set. A new link can be requested after 10 minutes.");
      } else {
        const result = await post(deleting ? '/api/delete-interest' : withdrawing ? '/api/withdraw-interest' : '/api/confirm-interest', { token });
        if (result.state !== (deleting ? 'erased' : withdrawing ? 'withdrawn' : 'confirmed')) throw new Error('Could not verify the result. Please try again.');
        setMessage(deleting ? 'Your live Pro-interest signup record has been deleted.' : withdrawing ? 'Your Pro interest has been withdrawn. Your release-update preference is unchanged.' :
          "You're on the Pro-interest list. Thanks for helping shape what comes next. Your release-update preference is unchanged.");
      }
      setStatus('success');
    } catch (error) {
      setStatus('error');
      setMessage(error.name === 'AbortError' ? 'That took too long. Please try again later.' : error.message);
    }
  }

  async function requestErasure() {
    setErasureStatus('submitting'); setErasureMessage('Sending…');
    try {
      const result = await post('/api/request-interest-erasure', { token });
      if (result.state !== 'erasure_pending') throw new Error('Could not verify the deletion request. Please try again.');
      setErasureStatus('success');
      setErasureMessage('Check your email for a fresh deletion link. If you just requested one, use that email or wait 10 minutes before trying again.');
    } catch (error) {
      setErasureStatus('error');
      setErasureMessage(error.name === 'AbortError' ? 'That took too long. Please try again later.' : error.message);
    }
  }

  if (mode !== 'request') return (
    <section className="interest-page interest-action" aria-labelledby="interest-title">
      <p className="section-label">EXP Pro · proposed</p>
      <h1 id="interest-title">{deleting ? 'Delete your Pro-interest record.' : withdrawing ? 'Withdraw your interest.' : 'One more step.'}</h1>
      <p>{deleting ? 'Remove your email, payment-model preference and permission record from the live Pro-interest database.' : withdrawing ? 'Stop emails about the proposed EXP Pro offer and feedback invitations.' : permission}</p>
      <p>{deleting ? 'This deletes only the Pro-interest signup record. Your release notifications and local design files are separate. Copies in sent email, provider logs and backups follow their own retention rules.' : withdrawing ? 'This also cancels an unconfirmed Pro request.' : 'Confirming joins only the Pro-interest list. No purchase, account or general marketing subscription.'}</p>
      {deleting && <p>Any free-account connection becomes inactive. <a href="/account/pro">Disconnect it in your account</a> to remove that saved reference too.</p>}
      <form onSubmit={submit}>
        <button className="interest-button" type="submit" disabled={busy || done || !hasToken}>
          {busy ? 'Working…' : deleting ? 'delete my Pro-interest record' : withdrawing ? 'withdraw Pro interest' : 'confirm Pro interest'}
        </button>
        {!hasToken && (deleting
          ? <p>Open the complete deletion link from your email. It expires after 15 minutes; you can request a fresh one from your original withdrawal page.</p>
          : withdrawing
          ? <p>Open the complete withdrawal link from your confirmation email.</p>
          : <p>Open the complete link from your email. If it expired, <a href="/pro">request a new confirmation</a>.</p>)}
        <p className={`interest-message ${status}`} role="status">{message}</p>
      </form>
      {withdrawing && hasToken && !done && <section className="interest-erasure" aria-labelledby="connect-account-title">
        <h2 id="connect-account-title">Manage this from your free account</h2>
        <p>A confirmed Pro-interest record can be connected to an EXP account with the same email. You’ll sign in and choose to connect it; your email permission stays unchanged.</p>
        <a className="interest-text-link" href={`/account/pro#${token}`}>Connect to my free account</a>
      </section>}
      {withdrawing && <section className="interest-erasure" aria-labelledby="erasure-title">
        <h2 id="erasure-title">Want the signup record deleted too?</h2>
        <p>Withdrawal stops Pro-interest emails. Deletion also removes your live Pro-interest signup record. We'll send a fresh confirmation link to your email first.</p>
        <button className="interest-button" type="button" onClick={requestErasure}
          disabled={!hasToken || busy || erasureStatus === 'submitting' || erasureStatus === 'success'}>
          {erasureStatus === 'submitting' ? 'Sending…' : 'email me a deletion link'}
        </button>
        <p className={`interest-message ${erasureStatus}`} role="status">{erasureMessage}</p>
      </section>}
      <a className="interest-text-link" href="/download">get the free app</a>
    </section>
  );

  return (
    <section className="interest-page" aria-labelledby="interest-title">
      <div className="interest-intro">
        <p className="section-label">EXP Pro · proposed</p>
        <h1 id="interest-title">Help shape what comes next.</h1>
        <p className="interest-lead">A useful paid addition should earn its place in your workflow.</p>
        <p>I'm exploring optional paid additions to EXP [design]. Before choosing the offer,
          I'd like to hear from people who might use them.</p>
        <p>The shipped editor and exports stay free. There's no payment here, and no
          promised price or release date.</p>
        <a className="interest-text-link" href="/download">just here for the free app? download it here.</a>
      </div>
      <form className="interest-form glass-thick glass-edge" onSubmit={submit} aria-labelledby="pro-form-title">
        <h2 id="pro-form-title">keep me in the loop</h2>
        <p>Pro-offer updates and a feedback invitation. Separate from release notifications.</p>
        <label htmlFor="pro-email">email (required)</label>
        <input id="pro-email" type="email" autoComplete="email" maxLength={254} required
          value={email} onChange={event => setEmail(event.target.value)} disabled={busy || done} />
        <label htmlFor="pro-model">which payment model would you consider? (required)</label>
        <select id="pro-model" required value={model} onChange={event => setModel(event.target.value)} disabled={busy || done}>
          <option value="">choose a preference</option>
          <option value="one_time">one-time purchase</option>
          <option value="subscription">subscription</option>
          <option value="either">I'd consider either — depending on the benefit</option>
        </select>
        <p className="interest-hint">A preference helps guide the conversation; it isn't a purchase commitment.</p>
        <div className="interest-permission">
          <input id="pro-permission" type="checkbox" required checked={consent}
            onChange={event => setConsent(event.target.checked)} disabled={busy || done} />
          <label htmlFor="pro-permission">{permission} (required)</label>
        </div>
        <label className="signup-trap" htmlFor="pro-website">website</label>
        <input className="signup-trap" id="pro-website" type="text" tabIndex={-1} autoComplete="off"
          value={website} onChange={event => setWebsite(event.target.value)} />
        <button className="interest-button" type="submit" disabled={busy || done}>{busy ? 'Sending…' : 'email me a confirmation'}</button>
        <p className="interest-hint">You'll join after confirming your email. The email also includes a link to withdraw your interest.</p>
        <p className={`interest-message ${status}`} role="status">{message}</p>
      </form>
    </section>
  );
}
