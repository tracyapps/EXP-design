import React, { useEffect, useRef, useState } from 'react';
import './account.css';
import BetaPage from './BetaPage.jsx';
import AccountProPage from './AccountProPage.jsx';
import CommunityPage from './CommunityPage.jsx';
import NewsPreferences from './NewsPreferences.jsx';
import TicketsPage from './TicketsPage.jsx';
import accountRequest from './account-request.js';


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
  const [proToken, setProToken] = useState(() => path === '/account/pro' ? window.location.hash.slice(1) : '');

  function receive(next) {
    setUser(next);
    if (next) {
      setProfile({ name: next.name, bio: next.bio, link: next.link });
      setLargeText(next.largeText);
    } else { setProfile({ name: '', bio: '', link: '' }); setLargeText(false); }
  }
  useEffect(() => {
    if (path === '/account/pro') window.history.replaceState(null, '', window.location.pathname);
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
          setProToken('');
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
  const section = path === '/account/profile' ? 'profile' : path === '/account/preferences' ? 'preferences' : path === '/account/beta' ? 'beta' : path === '/account/pro' ? 'pro' : path === '/account/community' ? 'community' : path === '/account/tickets' ? 'tickets' : path === '/account/support' ? 'support' : 'home';
  return <section className={`account-page${user?.largeText ? ' account-large-text' : ''}`} aria-labelledby="account-title">
    <p className="section-label">EXP [design] · free account</p>
    <h1 id="account-title" tabIndex={-1} ref={headingRef}>{user ? section === 'profile' ? 'Your private profile.' : section === 'preferences' ? 'Your preferences.' : section === 'beta' ? 'Help shape EXP.' : section === 'pro' ? 'Your Pro interest.' : section === 'community' ? 'Your community profile.' : section === 'tickets' ? 'Your private tickets.' : section === 'support' ? 'EXP support inbox.' : `Hello, ${user.name}.` : 'A place for you.'}</h1>
    <p className="account-lead">{user ? 'Your account details stay private. You choose whether to publish a separate community profile.' : 'An optional account, separate from your design files. The editor and shipped exports stay free to use without signing in.'}</p>
    <p className="account-status" role="status">{message}</p>
    {!user && proToken && <p>Sign in with the email used for Pro interest, then choose whether to connect that record. Signing in does not subscribe you. Reopen the email link if this page is reloaded.</p>}
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
        <a href="/account/pro" aria-current={section === 'pro' ? 'page' : undefined}>Pro interest</a>
        <a href="/account/community" aria-current={section === 'community' ? 'page' : undefined}>Community profile</a>
        <a href="/news">News & updates</a>
        <a href="/account/tickets" aria-current={section === 'tickets' ? 'page' : undefined}>My tickets</a>
      </nav>
      {section === 'home' && <div className="account-card">
        <h2>Your account is ready.</h2>
        <p>Signed in as <strong>{user.email}</strong>. Edit your private profile or choose larger text for this account area.</p>
        <p><a href="/pro">Help shape EXP Pro</a> uses its own confirmation and permission. <a href="/support.html">Support the developer</a> is optional and account-free.</p>
        <p><a href="/account/beta">Choose beta participation or send private feedback</a>. <a href="/account/community">Prepare an optional community profile</a>. <a href="/news">Read news and updates</a> or <a href="/account/tickets">open a private support ticket</a>.</p>
      </div>}
      {section === 'profile' && <form className="account-card" onSubmit={e => { e.preventDefault(); act({ action: 'save-profile', ...profile }, 'Private profile saved.'); }}>
        <fieldset disabled={busy}><legend>Private profile</legend>
          <label htmlFor="profile-name">Display name</label>
          <input id="profile-name" required maxLength={80} autoComplete="nickname" value={profile.name} onChange={e => setProfile({ ...profile, name: e.target.value })} />
          <label htmlFor="profile-bio">Bio (optional, up to 500 characters)</label>
          <textarea id="profile-bio" rows={4} maxLength={500} value={profile.bio} onChange={e => setProfile({ ...profile, bio: e.target.value })} />
          <label htmlFor="profile-link">Website (optional HTTPS link)</label>
          <input id="profile-link" type="url" maxLength={300} value={profile.link} onChange={e => setProfile({ ...profile, link: e.target.value })} />
          <p>Only you can view this profile in the member area. Your optional community profile has its own details and publication choice.</p>
          <button type="submit">Save private profile</button>
        </fieldset>
      </form>}
      {section === 'beta' && <BetaPage key={user.id} request={accountRequest} onSignedOut={() => { receive(null); setSent(false); setMessage('Please sign in again.'); window.requestAnimationFrame(() => headingRef.current?.focus()); }} />}
      {section === 'pro' && <AccountProPage key={user.id} request={accountRequest} token={proToken} clearToken={() => setProToken('')} onSignedOut={() => { receive(null); setProToken(''); setSent(false); setMessage('Please sign in again.'); window.requestAnimationFrame(() => headingRef.current?.focus()); }} />}
      {section === 'community' && <CommunityPage key={user.id} request={accountRequest} onSignedOut={() => { receive(null); setSent(false); setMessage('Please sign in again.'); window.requestAnimationFrame(() => headingRef.current?.focus()); }} />}
      {['tickets','support'].includes(section) && <TicketsPage key={user.id} request={accountRequest} support={section==='support'} onSignedOut={() => { receive(null); setSent(false); setMessage('Please sign in again.'); }} />}
      {section === 'preferences' && <NewsPreferences key={user.id} request={accountRequest} onSignedOut={() => { receive(null); setSent(false); setMessage('Please sign in again.'); }} />}
      {section === 'preferences' && <form className="account-card" onSubmit={e => { e.preventDefault(); act({ action: 'save-preferences', largeText }, 'Account text preference saved.'); }}>
        <fieldset disabled={busy}><legend>Account display</legend>
          <label className="account-check"><input type="checkbox" checked={largeText} onChange={e => setLargeText(e.target.checked)} /><span>Use larger text in this account area</span></label>
          <p>This saves to your web account. It does not change the native editor’s interface settings.</p>
          <button type="submit">Save preferences</button>
        </fieldset>
        <h2>Email permissions stay separate.</h2>
        <p>Creating this account did not enroll you in release, news, beta or Pro marketing. <a href="/account/beta">Manage beta invitations</a> or <a href="/account/pro">connect your confirmed Pro interest</a>. Existing release-list permissions remain separate.</p>
        <p><a href="/pro">Review the proposed Pro-interest invitation</a>. Use the withdrawal link in your Pro-interest email to stop those messages.</p>
      </form>}
      <div className="account-session-actions">
        <button type="button" disabled={busy} onClick={() => act({ action: 'sign-out' }, 'Signed out on this browser.')}>Sign out</button>
        <button type="button" disabled={busy} onClick={() => act({ action: 'sign-out-all' }, 'Signed out everywhere.')}>Sign out everywhere</button>
      </div>
      {section === 'preferences' && <details className="account-card account-delete"><summary>Delete this free account</summary>
        <p>This removes your live account, private profile, account preferences, beta choices, feedback, Pro account connection, community draft/public profile, associated community reports, development-news permission, ticket email choice and queued alerts, your authored tickets and all their replies, support grants and sessions. Replies you wrote as support on other members’ tickets remain with those threads without your account ID. It does not remove local design files, separate release/Pro list permissions, sent email, provider logs or backups.</p>
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
