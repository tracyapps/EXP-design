import React, { useEffect, useId, useState } from 'react';
import accountRequest from './account-request.js';
import { useAccountSession } from './AccountSession.jsx';
import './engagement.css';

export default function ShareTools({ memberData, onChanged }) {
  const id = useId(), { user } = useAccountSession();
  const [loaded, setLoaded] = useState(null), [message, setMessage] = useState(''), [manualCopy, setManualCopy] = useState(false);
  useEffect(() => {
    let active = true;
    setLoaded(null);
    if (user && !memberData) accountRequest({ action: 'engagement' }).then(data => { if (active) setLoaded({ ownerId: user.id, value: data }); }).catch(() => { if (active) { setLoaded({ ownerId: user.id, value: { enabled: false } }); setMessage('Member sharing is unavailable. You can still share the public link.'); } });
    return () => { active = false; };
  }, [user?.id, memberData]);
  const data = memberData || (loaded && user && loaded.ownerId === user.id ? loaded.value : null);
  const url = data?.enabled && data.shareCode ? `https://expdesign.app/?ref=${data.shareCode}` : 'https://expdesign.app/';
  const text = 'EXP [design]: a native Mac design tool for making detailed work and handing it off. The editor and exports are free.';
  async function record(target) {
    if (!data?.enabled || !data.shareCode) return;
    try { await accountRequest({ action: 'record-member-share', id: crypto.randomUUID(), target, code: data.shareCode }); void Promise.resolve(onChanged?.()).catch(() => setMessage('Share action saved; reload your account to refresh totals.')); }
    catch { setMessage('Your share action worked, but its account record could not be saved. No referral credit is promised.'); }
  }
  async function copy() {
    try { await navigator.clipboard.writeText(url); setMessage('Link copied. Share it wherever it’s useful.'); setManualCopy(false); await record('copy'); }
    catch { setManualCopy(true); setMessage('Select and copy the link below. No share action has been recorded.'); }
  }
  async function nativeShare() {
    try { await navigator.share({ title: 'EXP [design]', text, url }); setMessage('Share sheet completed. This does not verify a post or delivery.'); await record('system'); }
    catch (error) { if (error.name !== 'AbortError') { setMessage('Sharing isn’t available here. Try copying the link.'); } }
  }
  const targets = [
    ['email', 'email a friend', `mailto:?subject=${encodeURIComponent('A Mac design tool you might like')}&body=${encodeURIComponent(`${text}\n\n${url}`)}`],
    ['linkedin', 'LinkedIn', `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`],
    ['bluesky', 'Bluesky', `https://bsky.app/intent/compose?text=${encodeURIComponent(`${text} ${url}`)}`],
    ['facebook', 'Facebook', `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(url)}`]
  ];
  return <section className="share-tools" aria-labelledby={`${id}-title`}>
    <div><p className="section-label">good tools travel by word of mouth</p><h2 id={`${id}-title`}>Know someone who would make something with EXP?</h2>
      <p>Send them a link. No signup is required to try the app. <a href="/share">Get logos, images and words to share.</a></p></div>
    <div className="share-actions"><button className="button secondary" type="button" onClick={copy}>copy link</button>
      {typeof navigator.share === 'function' && <button className="button secondary" type="button" onClick={nativeShare}>share…</button>}
      {targets.map(([target,label,href]) => <a key={target} className="button secondary" href={href} target={target === 'email' ? undefined : '_blank'} rel="noreferrer" onClick={() => { void record(target); }}>{label}</a>)}
    </div>
    {manualCopy && <label className="manual-share-link">Link to copy<input readOnly value={url} onFocus={event => event.target.select()} /></label>}
    <p className="member-small">{data?.enabled && data.shareCode ? 'This is your member link. New members can choose to credit you. Account records count share actions and consented signups, not verified posts or sales. There are no rewards or referral benefits promised.' : user ? 'Member sharing may still be loading or paused. The public link remains available; no member credit is attached to it.' : 'Create an account to use a personal member link. Sharing the public link is always available.'}</p>
    <p role="status" className="account-status">{message}</p>
  </section>;
}
