import React,{useEffect} from 'react';
import './account.css';
import MemberCallout from './MemberCallout.jsx';
import { registrationHref } from './engagement-links.js';
export default function AccountsIntro() {
  useEffect(()=>{document.title='About free EXP accounts — EXP [design]';},[]);
  return <section className="account-page" aria-labelledby="accounts-about-title">
    <p className="section-label">EXP [design] · free accounts</p>
    <h1 id="accounts-about-title">Your corner of EXP.</h1>
    <p className="account-lead">A place for your profile, preferences and conversations about EXP. Creating an account is optional.</p>
    <p><a href={registrationHref()}>Create a free account</a> · <a href="/account">Sign in</a> · <a href="/download">Download EXP</a></p>
    <div className="account-card"><h2>Use the app without signing in.</h2>
      <p>The editor and shipped exports work without an account. Your design files stay on your Mac; signing in to this website does not upload or sync them.</p>
    </div>
    <div className="account-card"><h2>What your account is for today.</h2>
      <ul><li>A private profile and optional profile photo.</li><li>Preferences for this website’s account area.</li><li>Private feedback and feature requests, with a separate optional testimonial permission. Beta participation and Pro interest remain separate choices.</li><li>A place to read updates and manage your email choices.</li></ul>
      <p>Private support tickets and optional public community profiles are opening gradually. Their pages explain when new tickets, participation or publishing are paused.</p>
    </div>
    <div className="account-card"><h2>Your choices stay yours.</h2>
      <p>Your email and account photo are private. A community profile has its own details and an explicit publish step. An account does not automatically subscribe you to newsletters or Pro offers.</p>
      <p>You can change preferences, sign out everywhere or delete your account. Supporting the developer is optional and does not purchase Pro access.</p>
    </div>
    <div className="account-card"><h2>Ideas we’re exploring next.</h2>
      <p>A community showcase, shared templates, components, design languages and other resources, optional device/settings sync, a Discord connection, and closer account/news integration in the Mac app. These are future possibilities, with no release dates promised.</p>
      <p>Settings sync is not available today. There is no cloud document sync or collaborative editing attached to this account.</p>
    </div>
    <p><a href={registrationHref()}>Create a free account</a> whenever it is useful to you. <a href="/news">Follow what has shipped</a> without signing in.</p>
    <MemberCallout />
  </section>;
}
