import React, { useEffect } from 'react';
import './account.css';

// Curated public copy from RELEASE-NOTES-v2.6.md and the shipped release receipt.
// Internal roadmap/progress entries and account data are never this feed's source.
export default function NewsPage() {
  useEffect(()=>{document.title='News and updates — EXP [design]';},[]);
  return <section className="account-page" aria-labelledby="news-title">
    <p className="section-label">EXP [design]</p><h1 id="news-title">News and updates.</h1>
    <p className="account-lead">Release notes and occasional notes from the workbench. Read them here without an account.</p>
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
