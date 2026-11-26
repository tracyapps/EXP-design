import React from "react";

const assets = "/assets/design-language-v2-9";

function Screenshot({ file, alt, width, height, className = "" }) {
  const src = `${assets}/${file}.webp`;
  return (
    <a className={`dl-release-screenshot ${className}`} href={src}>
      <img src={src} alt={alt} width={width} height={height} loading="lazy" decoding="async" />
    </a>
  );
}

export default function DesignLanguageRelease() {
  return (
    <section id="design-language" className="design-language-section dl-release" aria-labelledby="design-language-title">
      <div className="section-copy dl-release-intro">
        <p className="section-label">new in EXP 2.9</p>
        <h2 id="design-language-title">Build a design language that stays with the work.</h2>
        <p>
          Link colors, type styles, spacing, corners, and borders to the layers that use them.
          Change a token once and see it update across the document.
        </p>
        <a className="button secondary" href="/news#release-29">What’s new in 2.9</a>
      </div>

      <div className="dl-release-modes">
        <div className="dl-release-copy">
          <h3>Put the same palette to work in every mode.</h3>
          <p>
            Set background and text defaults for each mode, then switch a whole page or override
            a single artboard. Give individual colors their own values when they need them.
          </p>
        </div>
        <Screenshot file="modes" width={1712} height={1188}
          alt="Open the full screenshot of Design Language settings with Light and Dark color columns and the Light mode icon menu" />
      </div>

      <div className="dl-release-features">
        <div className="dl-release-card">
          <div className="dl-release-copy">
            <h3>A guide that updates as you work.</h3>
            <p>Compare colors and contrast across modes, browse saved styles, and share an offline HTML guide with its token files.</p>
          </div>
          <Screenshot file="guide" width={1328} height={2048} className="dl-release-guide"
            alt="Open the full Design Language Guide screenshot with mode contrast, color swatches, and typography samples" />
        </div>
        <div className="dl-release-card">
          <div className="dl-release-copy">
            <h3>Go from table to code.</h3>
            <p>Copy CSS or SCSS into your project. For bulk changes, edit JSON with syntax highlighting and folding, then review before applying.</p>
          </div>
          <Screenshot file="css" width={1117} height={943}
            alt="Open the full Code view screenshot showing CSS variables for base, light, and dark modes" />
          <a className="dl-release-json" href={`${assets}/json.webp`}>See the JSON editor</a>
        </div>
      </div>
    </section>
  );
}
