import React, { useEffect, useRef, useState } from 'react';

const modelNames = { one_time: 'One-time purchase', subscription: 'Subscription', either: 'Either, depending on the benefit' };
export default function AccountProPage({ request, token, clearToken, onSignedOut }) {
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('Checking your Pro-interest connection…');
  const active = useRef(false);
  const hasToken = /^[A-Za-z0-9_-]{43}$/.test(token);
  useEffect(() => {
    active.current = true;
    request({ action: 'pro-interest' }).then(next => { if (active.current) { setData(next); setMessage(''); } })
      .catch(error => { if (active.current) { if (error.status === 401) onSignedOut(); else setMessage(error.message); } });
    return () => { active.current = false; };
  }, [request]);
  async function act(action, success) {
    if (busy) return;
    setBusy(true); setMessage('Working…');
    try {
      await request({ action, ...(action === 'link-pro-interest' ? { token } : {}) });
      if (!active.current) return;
      setData(null);
      if (action === 'link-pro-interest' || action === 'unlink-pro-interest') clearToken();
      try {
        const next = await request({ action: 'pro-interest' });
        if (!active.current) return;
        setData(next); setMessage(success);
      } catch (error) {
        if (!active.current) return;
        if (error.status === 401) onSignedOut();
        else setMessage(`${success} Reload to check the latest record; its details could not be refreshed.`);
      }
    } catch (error) {
      if (!active.current) return;
      if (error.status === 401) onSignedOut();
      else setMessage(error.name === 'TimeoutError' ? 'That took too long. Reload to check the result before trying again.' : error.message);
    } finally { if (active.current) setBusy(false); }
  }
  return <>
    <p className="account-status" role="status">{message}</p>
    <div className="account-card">
      <h2>Your proposed Pro offer</h2>
      <p>Pro interest is permission for emails about the proposed offer and a feedback invitation. It is separate from your account, beta and release notifications. No purchase or paid access is implied.</p>
      {data?.state === 'unlinked' && <p>No Pro-interest record is connected to this account. A matching email does not connect one automatically.</p>}
      {data?.state === 'confirmed' && <>
        <p>Pro-interest emails are on for your connected record.</p>
        <p>Payment-model preference: <strong>{modelNames[data.model]}</strong></p>
        <p>Confirmed <time dateTime={data.confirmedAt}>{new Date(data.confirmedAt).toLocaleString()}</time>.</p>
        <button type="button" disabled={busy} onClick={() => act('withdraw-pro-interest', 'Pro interest withdrawn. Your other email choices are unchanged.')}>Withdraw Pro-interest emails</button>
      </>}
      {data?.state === 'withdrawn' && <p>Pro-interest emails are off. Connecting or signing in again will not rejoin this list.</p>}
      {data?.state === 'pending' && <p>This connection has no confirmed Pro-interest permission. Use your confirmation email to finish the separate signup.</p>}
      {data?.state === 'unavailable' && <p>This record is no longer available through the saved connection. It may have been deleted or replaced. No active permission is assumed; disconnect it or use a fresh email link.</p>}
      {!data && <p><a href="/account/pro">Reload Pro interest</a></p>}
    </div>
    <div className="account-card">
      <h2>Connect an existing record</h2>
      <p>Open the withdrawal link in your Pro-interest email and choose “Connect to my free account.” Use the same verified email for both. You’ll review and connect explicitly here; opening a link does not change permission.</p>
      {hasToken && <>
        <p>Your email link is ready. Connecting lets this account view that record and withdraw its Pro-interest permission.</p>
        <button type="button" disabled={busy || !data?.linkingAvailable} onClick={() => act('link-pro-interest', 'Your confirmed Pro-interest record is connected. Email permission is unchanged.')}>Connect confirmed Pro interest</button>
      </>}
      {data && !data.linkingAvailable && <p>New account connections are not open right now. Existing connections can still be reviewed, withdrawn or disconnected.</p>}
      <p><a href="/pro">Review the proposed Pro invitation</a> if you haven’t joined yet. That signup has its own confirmation. Reloading this page clears an unused email link.</p>
      {data?.state !== 'unlinked' && <>
        <button type="button" className="account-secondary" disabled={busy} onClick={() => act('unlink-pro-interest', 'Account connection removed. The separate Pro-interest email choice is unchanged.')}>Disconnect account link</button>
        <p>Disconnecting removes the account reference. To stop Pro emails, withdraw first or use the email’s withdrawal link. Deleting your free account also leaves the separate Pro-interest permission unchanged.</p>
      </>}
    </div>
  </>;
}
