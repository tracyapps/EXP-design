import React, { useEffect } from 'react';
import './account.css';

// Curated public copy from RELEASE-NOTES-v2.6.md and the shipped release receipt.
// Internal roadmap/progress entries and account data are never this feed's source.
export default function NewsPage({ hasDesignLanguageRelease }) {
  useEffect(()=>{document.title='News and updates — EXP [design]';},[]);
  return <section className="account-page" aria-labelledby="news-title">
    <p className="section-label">EXP [design]</p><h1 id="news-title">News and updates.</h1>
    <p className="account-lead">Release notes and occasional notes from the workbench. Read them here without an account.</p>
    {hasDesignLanguageRelease && <article id="release-29" className="account-card" aria-labelledby="release-29-title">
      <h2 id="release-29-title">EXP 2.9 gives your design language more room to work.</h2>
      <p>Switch color modes by page or artboard, and link reusable spacing, corner radius, and border width to the artwork that uses them.</p>
      <p>Compare modes and contrast in a live Guide, export it with your token files, and switch between the token table and code whenever you need to edit or copy values.</p>
      <p><a href="/#design-language">See the new Design Language tools</a> · <a href="https://github.com/tracyapps/EXP-design/releases/tag/v2.9">Read the full release notes</a></p>
    </article>}
    <article className="account-card" aria-labelledby="release-26-title">
      <p>Release · <time dateTime="2026-10-02">October 2, 2026</time></p>
      <h2 id="release-26-title">EXP 2.6: a smoother canvas, and tools for everyday work.</h2>
      <p>Large design documents get faster selection, editing, panning and zooming. The freehand Knife follows your stroke, and Unite can collect compatible vectors from nested folders.</p>
      <p>Three independent appearance clipboards let you copy effects, style, or both. You can also save a named type style from Properties and export artboard notes as Markdown task lists.</p>
      <p>Build 17 requires macOS 26.2 or later. Complex pattern previews keep their editable sources and export fidelity.</p>
      <p><a href="/download">Get the free app</a> · <a href="/learn">Explore the tutorials</a></p>
    </article>
    <p><a href="/account/preferences">Manage optional development-news email permission</a>. Reading this page or creating an account does not subscribe you.</p>
  </section>;
}
