import React, { useId, useState } from 'react';
import { useAccountSession } from './AccountSession.jsx';
import { registrationHref, withReferral } from './engagement-links.js';
import './engagement.css';

export default function MemberCallout() {
  const id = useId(), { user } = useAccountSession();
  const [alsoPro, setAlsoPro] = useState(false), [alsoAccount, setAlsoAccount] = useState(false);
  return <section className="member-callout" aria-labelledby={`${id}-title`}>
    <div className="member-callout-intro"><p className="section-label">make yourself at home</p>
      <h2 id={`${id}-title`}>A useful app. A place to help shape it.</h2>
      <p>EXP is a native Mac design tool for making the work, keeping its detail, and handing it off. Try the free editor, then help decide what comes next.</p>
    </div>
    <div className="member-callout-grid">
      <div className="member-callout-card member-callout-account glass-edge">
        <p className="section-label">free EXP account</p><h3>Your corner of EXP.</h3>
        <p>A home for your profile, preferences and conversations about the app.</p>
        <ul><li>Keep your private profile and email choices in one place.</li>
          <li>Read news, follow your support tickets, and send feedback or feature requests.</li>
          <li>Share EXP with a personal link and review the signup credit people choose to give you.</li></ul>
        <p className="member-future"><strong>On the roadmap:</strong> a community showcase, shared templates, components and design languages, and optional device sync. These aren’t available yet.</p>
        {!user && <label className="engagement-check"><input type="checkbox" checked={alsoPro} onChange={e => setAlsoPro(e.target.checked)} />I’d also like to explore Pro interest after creating my account.</label>}
        <a className="button primary" href={user ? '/account' : registrationHref(alsoPro)}>{user ? 'open my account' : 'create a free account'} <span aria-hidden="true">↗</span></a>
        <p className="member-small">Account tools are opening gradually. Editing and exporting work without an account. Your files stay on your Mac.</p>
      </div>
      <div className="member-callout-card member-callout-pro glass-edge">
        <div className="member-pro-heading"><p className="section-label">EXP Pro · exploring</p><img src="/assets/pro.svg" width="990" height="674" alt="" /></div>
        <h3>What would make Pro worth it to you?</h3>
        <p>Help shape an optional paid addition that earns its place in your workflow.</p>
        <p>Tell me you’re interested, choose the payment model you’d consider, and get an invitation to give feedback.</p>
        {!user && <label className="engagement-check"><input type="checkbox" checked={alsoAccount} onChange={e => setAlsoAccount(e.target.checked)} />I’d also like to create a free account afterward.</label>}
        <a className="button secondary" href={withReferral(`/pro${alsoAccount ? '?next=account' : ''}`)}>I’m interested in Pro <span aria-hidden="true">↗</span></a>
        <p className="member-small">Interest only. No checkout, promised features, price or release date. Each choice has its own confirmation; neither subscribes you to the other.</p>
      </div>
    </div>
  </section>;
}
