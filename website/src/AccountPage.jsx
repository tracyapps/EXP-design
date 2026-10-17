import React, { useEffect, useRef, useState } from 'react';
import './account.css';
import BetaPage from './BetaPage.jsx';

async function accountRequest(body) {
  const response = await fetch('/api/account', { method: body ? 'POST' : 'GET', credentials: 'same-origin',
    cache: 'no-store', signal: AbortSignal.timeout(15000),
    headers: body ? { 'content-type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.ok !== true) {
    const error = new Error(result.error || 'Account service is unavailable. Please try later.');
    error.status = response.status; throw error;
  }
  return result;
}

export default function AccountPage({ path }) {
  const headingRef = useRef(null);
  const codeRef = useRef(null);
  const emailRef = useRef(null);
  const [user, setUser] = useState(null);
  const [ready, setReady] = useState(false);
  const [available, setAvailable] = useState(false);
  const [registrationOpen, setRegistrationOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('Checking account availability…');
  const [intent, setIntent] = useState('sign-in');
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [consent, setConsent] = useState(false);
  const [sent, setSent] = useState(false);
  const [otp, setOTP] = useState('');
  const [profile, setProfile] = useState({ name: '', bio: '', link: '' });
  const [largeText, setLargeText] = useState(false);
  const [confirmation, setConfirmation] = useState('');

  function receive(next) {
    setUser(next);
    if (next) {
      setProfile({ name: next.name, bio: next.bio, link: next.link });
      setLargeText(next.largeText);
    } else { setProfile({ name: '', bio: '', link: '' }); setLargeText(false); }
  }
  useEffect(() => {
    document.title = 'Your free account — EXP [design]';
    let active = true;
    accountRequest().then(result => {
      if (active) { receive(result.user); setRegistrationOpen(result.registrationOpen); setAvailable(true); setMessage(''); }
    }).catch(error => { if (active) setMessage(error.message); })
      .finally(() => { if (active) setReady(true); });
    return () => { active = false; };
  }, []);
  useEffect(() => { if (sent) codeRef.current?.focus(); }, [sent]);

  async function act(body, success) {
    setBusy(true); setMessage('Working…');
    try {
      await accountRequest(body);
      if (body.action === 'send-code') { setSent(true); setOTP(''); }
      else {
        if (['sign-out', 'sign-out-all', 'delete-account'].includes(body.action)) {
          receive(null);
          setSent(false); setOTP(''); setConfirmation(''); setConsent(false);
        } else receive((await accountRequest()).user);
      }
      setMessage(success);
      if (['verify-code', 'sign-out', 'sign-out-all', 'delete-account'].includes(body.action)) {
        setOTP('');
        window.requestAnimationFrame(() => headingRef.current?.focus());
      }
    } catch (error) {
      if (error.status === 401) { receive(null); setSent(false); }
      setMessage(error.name === 'TimeoutError' ? 'That took too long. Please try again later.' : error.message);
    } finally { setBusy(false); }
  }
  const section = path === '/account/profile' ? 'profile' : path === '/account/preferences' ? 'preferences' : path === '/account/beta' ? 'beta' : 'home';
  return <section className={`account-page${user?.largeText ? ' account-large-text' : ''}`} aria-labelledby="account-title">
    <p className="section-label">EXP [design] · free account</p>
    <h1 id="account-title" tabIndex={-1} ref={headingRef}>{user ? section === 'profile' ? 'Your private profile.' : section === 'preferences' ? 'Your preferences.' : section === 'beta' ? 'Help shape EXP.' : `Hello, ${user.name}.` : 'A place for you.'}</h1>
    <p className="account-lead">{user ? 'Your profile is private. You choose what comes next.' : 'An optional account, separate from your design files. The editor and shipped exports stay free to use without signing in.'}</p>
    <p className="account-status" role="status">{message}</p>
    {!ready && <p>Loading…</p>}
    {ready && !available && <p>Account registration is not available right now. <a href="/account">Check again</a> or <a href="/download">get the free app</a>.</p>}
    {ready && available && !user && <form className="account-card" onSubmit={event => {
      event.preventDefault();
      act(sent ? { action: 'verify-code', email, otp, intent, name, accountConsent: consent, consentVersion: 'free-account-v1' } :
        { action: 'send-code', email }, sent ? 'You’re signed in.' : 'Code sent. Check your inbox; it expires in five minutes. You can request another after one minute.');
    }}>
      <fieldset disabled={busy}>
        <legend>{sent ? 'Enter your email code' : 'Sign in or create an account'}</legend>
        <div className="account-options">
          <label><input type="radio" name="intent" value="sign-in" checked={intent === 'sign-in'} onChange={() => setIntent('sign-in')} /> Sign in</label>
          {registrationOpen && <label><input type="radio" name="intent" value="register" checked={intent === 'register'} onChange={() => setIntent('register')} /> Create account</label>}
        </div>
        <label htmlFor="account-email">Email address</label>
        <input id="account-email" ref={emailRef} type="email" autoComplete="email" required maxLength={254} value={email} readOnly={sent} onChange={e => setEmail(e.target.value)} />
        {intent === 'register' && <>
          <label htmlFor="account-name">Display name</label>
          <input id="account-name" autoComplete="nickname" required maxLength={80} value={name} onChange={e => setName(e.target.value)} />
          <label className="account-check"><input type="checkbox" required checked={consent} onChange={e => setConsent(e.target.checked)} />
            <span>Create my optional EXP account and store my private profile. This does not subscribe me to email updates or Pro offers.</span></label>
        </>}
        {sent && <><label htmlFor="account-code">Six-digit code</label>
          <input id="account-code" ref={codeRef} inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" minLength={6} maxLength={6} required value={otp} onChange={e => setOTP(e.target.value)} />
        </>}
        <button type="submit">{busy ? 'Working…' : sent ? intent === 'register' ? 'Create my account' : 'Sign in' : 'Email me a code'}</button>
        {sent && <button type="button" className="account-secondary" onClick={() => { setSent(false); setOTP(''); setMessage('Request a fresh code or use another email address.'); emailRef.current?.focus(); }}>Use another email or request a new code</button>}
      </fieldset>
      {!registrationOpen && <p>New account registration is paused. Existing members can still sign in and manage their account.</p>}
      <p>No password to remember. Signing in again requires a new email code. Email access is needed to recover access; changing the account email is a later slice.</p>
    </form>}
    {ready && user && <>
      <nav className="account-nav" aria-label="Your account">
        <a href="/account" aria-current={section === 'home' ? 'page' : undefined}>Overview</a>
        <a href="/account/profile" aria-current={section === 'profile' ? 'page' : undefined}>Private profile</a>
        <a href="/account/preferences" aria-current={section === 'preferences' ? 'page' : undefined}>Preferences</a>
        <a href="/account/beta" aria-current={section === 'beta' ? 'page' : undefined}>Beta & feedback</a>
      </nav>
      {section === 'home' && <div className="account-card">
        <h2>Your account is ready.</h2>
        <p>Signed in as <strong>{user.email}</strong>. Edit your private profile or choose larger text for this account area.</p>
        <p><a href="/pro">Help shape EXP Pro</a> uses its own confirmation and permission. <a href="/support.html">Support the developer</a> is optional and account-free.</p>
        <p><a href="/account/beta">Choose beta participation or send private feedback</a>. Public community profiles, news preferences and ticket replies are planned next.</p>
      </div>}
      {section === 'profile' && <form className="account-card" onSubmit={e => { e.preventDefault(); act({ action: 'save-profile', ...profile }, 'Private profile saved.'); }}>
        <fieldset disabled={busy}><legend>Private profile</legend>
          <label htmlFor="profile-name">Display name</label>
          <input id="profile-name" required maxLength={80} autoComplete="nickname" value={profile.name} onChange={e => setProfile({ ...profile, name: e.target.value })} />
          <label htmlFor="profile-bio">Bio (optional, up to 500 characters)</label>
          <textarea id="profile-bio" rows={4} maxLength={500} value={profile.bio} onChange={e => setProfile({ ...profile, bio: e.target.value })} />
          <label htmlFor="profile-link">Website (optional HTTPS link)</label>
          <input id="profile-link" type="url" maxLength={300} value={profile.link} onChange={e => setProfile({ ...profile, link: e.target.value })} />
          <p>Only you can view this profile in the member area. Nothing is published to a community directory.</p>
          <button type="submit">Save private profile</button>
        </fieldset>
      </form>}
      {section === 'beta' && <BetaPage key={user.id} request={accountRequest} onSignedOut={() => { receive(null); setSent(false); setMessage('Please sign in again.'); window.requestAnimationFrame(() => headingRef.current?.focus()); }} />}
      {section === 'preferences' && <form className="account-card" onSubmit={e => { e.preventDefault(); act({ action: 'save-preferences', largeText }, 'Account text preference saved.'); }}>
        <fieldset disabled={busy}><legend>Account display</legend>
          <label className="account-check"><input type="checkbox" checked={largeText} onChange={e => setLargeText(e.target.checked)} /><span>Use larger text in this account area</span></label>
          <p>This saves to your web account. It does not change the native editor’s interface settings.</p>
          <button type="submit">Save preferences</button>
        </fieldset>
        <h2>Email permissions stay separate.</h2>
        <p>Creating this account did not enroll you in release, news, beta or Pro marketing. <a href="/account/beta">Manage beta invitations</a> separately. Existing release/Pro list permissions are separate; this area does not yet display or change them.</p>
        <p><a href="/pro">Review the proposed Pro-interest invitation</a>. Use the withdrawal link in your Pro-interest email to stop those messages.</p>
      </form>}
      <div className="account-session-actions">
        <button type="button" disabled={busy} onClick={() => act({ action: 'sign-out' }, 'Signed out on this browser.')}>Sign out</button>
        <button type="button" disabled={busy} onClick={() => act({ action: 'sign-out-all' }, 'Signed out everywhere.')}>Sign out everywhere</button>
      </div>
      {section === 'preferences' && <details className="account-card account-delete"><summary>Delete this free account</summary>
        <p>This removes your live account, private profile, account preferences, beta choices, feedback and sessions. It does not remove local design files, separate release/Pro list permissions, sent email, provider logs or backups.</p>
        <p>Sign in with a fresh email code, then confirm within five minutes. This cannot be undone.</p>
        <form onSubmit={e => { e.preventDefault(); act({ action: 'delete-account', confirmation }, 'Your live free account has been deleted. Separate email permissions are unchanged.'); }}>
          <fieldset disabled={busy}><legend>Confirm account deletion</legend>
            <label htmlFor="account-delete-confirm">Type DELETE to confirm</label>
            <input id="account-delete-confirm" autoComplete="off" required pattern="DELETE" value={confirmation} onChange={e => setConfirmation(e.target.value)} />
            <button type="submit">Delete my free account</button>
          </fieldset>
        </form>
      </details>}
    </>}
  </section>;
}
