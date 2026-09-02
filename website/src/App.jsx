import React, { useEffect, useMemo, useState } from "react";
import siteContent from "./generated/siteContent.json";
import {
  findHelpArticle,
  helpArticles,
  helpCategories,
  searchableHelpText,
} from "./helpContent";

const releaseUrl = "https://github.com/tracyapps/EXP-design/releases/latest";
const releasesUrl = "https://github.com/tracyapps/EXP-design/releases";
const issuesUrl = "https://github.com/tracyapps/EXP-design/issues/new";

// One nav for every page. Feature callouts live on the homepage; the dropdown
// jump-links to them with absolute /#anchor hrefs so they also work from
// /download and /learn.
const featureLinks = [
  { label: "features", href: "/#features" },
  { label: "Sanaa", href: "/#sanaa" },
  { label: "components", href: "/#component-system" },
  { label: "accessibility", href: "/#accessibility" },
  { label: "design language", href: "/#design-language" },
  { label: "import + handoff", href: "/#import-handoff" },
  { label: "multi-window", href: "/#workspace" },
];

const learnLinks = [
  { label: "tutorials", href: "/learn" },
  { label: "ARIA roles guide", href: "/aria-roles/" },
];

const navItems = [
  { label: "features", dropdown: featureLinks },
  { label: "learn", dropdown: learnLinks },
  { label: "roadmap", href: "/#roadmap" },
  { label: "download", href: "/download" },
];

const featureMoments = [
  {
    id: "canvas",
    title: "native canvas",
    icon: "ph-corners-out",
    line: "pan, zoom, rulers, guides, grids, masks, and artboards stay crisp because the core surface is AppKit and Core Graphics.",
    detail: "the canvas is intentionally undesigned. it gives your artboards the room.",
  },
  {
    id: "components",
    title: "components with a memory",
    icon: "ph-stack",
    line: "nest sources, describe states, expose the right properties, and keep every override attached to the instance that owns it.",
    detail: "reuse stays powerful without turning the layer tree into a guessing game.",
  },
  {
    id: "meaning",
    title: "accessible by intent",
    icon: "ph-person-arms-spread",
    line: "plain-language guidance keeps roles, names, relationships, text meaning, and contrast close to the decisions that create them.",
    detail: "accessibility is part of the design model—not a checklist waiting at the finish line.",
  },
];

function useScrollProgress() {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const update = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      setProgress(max > 0 ? window.scrollY / max : 0);
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    return () => {
      window.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
    };
  }, []);

  return progress;
}

function NavDropdown({ item }) {
  const [open, setOpen] = useState(false);
  const ref = React.useRef(null);
  const closeTimer = React.useRef(null);

  const clearCloseTimer = () => {
    if (closeTimer.current) {
      window.clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
  };
  // Hover-intent close: give the pointer time to travel from the trigger down
  // into the menu instead of slamming shut the instant the pointer leaves the
  // trigger's own box. Paired with the .nav-menu bridge in styles.css, which
  // closes the dead gap the pointer used to fall through.
  const openNow = () => {
    clearCloseTimer();
    setOpen(true);
  };
  const closeSoon = () => {
    clearCloseTimer();
    closeTimer.current = window.setTimeout(() => setOpen(false), 300);
  };

  useEffect(() => clearCloseTimer, []);

  useEffect(() => {
    if (!open) return undefined;
    function onPointerDown(event) {
      if (ref.current && !ref.current.contains(event.target)) setOpen(false);
    }
    // Also close when keyboard focus leaves the whole control, so a menu
    // opened via ArrowDown never gets stranded open after tabbing past it.
    function onFocusOut(event) {
      if (ref.current && !ref.current.contains(event.relatedTarget)) setOpen(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    const node = ref.current;
    node?.addEventListener("focusout", onFocusOut);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      node?.removeEventListener("focusout", onFocusOut);
    };
  }, [open]);

  return (
    <div
      className={open ? "nav-dropdown open" : "nav-dropdown"}
      ref={ref}
      onMouseEnter={openNow}
      onMouseLeave={closeSoon}
    >
      <button
        type="button"
        className="nav-dropdown-trigger"
        aria-haspopup="true"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        onKeyDown={(event) => {
          if (event.key === "Escape") setOpen(false);
          if (event.key === "ArrowDown") { event.preventDefault(); setOpen(true); }
        }}
      >
        {item.label}
        <i className="ph ph-caret-down" aria-hidden="true" />
      </button>
      <div className="nav-menu" role="menu">
        {item.dropdown.map((link) => (
          <a key={link.href} href={link.href} role="menuitem" onClick={() => setOpen(false)}>
            {link.label}
          </a>
        ))}
      </div>
    </div>
  );
}

function Nav({ items }) {
  return (
    <nav aria-label="primary">
      {items.map((item) =>
        item.dropdown ? (
          <NavDropdown key={item.label} item={item} />
        ) : (
          <a key={item.href} href={item.href}>
            {item.label}
          </a>
        ),
      )}
    </nav>
  );
}

function Header({
  progress,
  items = navItems,
  actionLabel = "tester download",
  actionHref = "/download",
  brandHref = "#top",
}) {
  const release = siteContent.release;
  const relDate = release?.date ? new Date(`${release.date}T00:00:00`) : null;
  const dateShort = relDate
    ? new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(relDate)
    : "";
  const dateLong = relDate
    ? new Intl.DateTimeFormat("en", { month: "long", day: "numeric", year: "numeric" }).format(relDate)
    : "";

  return (
    <header className="site-header glass-thin glass-edge">
      <a className="brand-lockup" href={brandHref} aria-label="EXP [design] home">
        <img src="/assets/exp-logo.png" alt="" />
        <span>EXP<span>[design]</span></span>
      </a>
      <Nav items={items} />
      <div className="header-cta">
        {release?.version && (
          <a
            className="version-pill"
            href="/download#download-signup"
            aria-label={`current version ${release.version}${dateLong ? `, released ${dateLong}` : ""}`}
          >
            <span className="version-num">v{release.version}</span>
            {dateShort && <span className="version-date">{dateShort}</span>}
          </a>
        )}
        <a className="header-action" href={actionHref}>
          {actionLabel}
        </a>
      </div>
      <div className="scroll-progress" style={{ transform: `scaleX(${progress})` }} />
    </header>
  );
}

function ProductWindow({ compact = false }) {
  return (
    <figure className={compact ? "product-window compact" : "product-window"}>
      <div className="window-bar" aria-hidden="true">
        <span className="traffic red" />
        <span className="traffic yellow" />
        <span className="traffic green" />
        <span className="window-title">EXP [design]</span>
      </div>
      <img
        src="/assets/exp-canvas-workbench-v2-1.png"
        alt="EXP design workspace with page tabs, an expanded component in Layers, artboards on the canvas, and component, Design Language, and Handoff panels"
      />
    </figure>
  );
}

function Hero() {
  const [tilt, setTilt] = useState({ x: 0, y: 0 });

  const heroStyle = useMemo(
    () => ({
      "--tilt-x": `${tilt.y * -4}deg`,
      "--tilt-y": `${tilt.x * 5}deg`,
    }),
    [tilt],
  );

  function handlePointerMove(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    setTilt({
      x: (event.clientX - rect.left) / rect.width - 0.5,
      y: (event.clientY - rect.top) / rect.height - 0.5,
    });
  }

  function clearTilt() {
    setTilt({ x: 0, y: 0 });
  }

  return (
    <section id="top" className="hero-section" onPointerMove={handlePointerMove} onPointerLeave={clearTilt} style={heroStyle}>
      <div className="hero-copy">
        <h1>a design tool that gets out of the way.</h1>
        <p>
          EXP [design] is a native macOS design app built around real UX workflow:
          fast canvas work, understandable components, accessibility-aware design,
          and flexible ways to bring work in or hand it onward.
        </p>
        <div className="hero-actions" aria-label="primary actions">
          <a className="button primary" href="/download">tester download</a>
          <a className="button secondary" href="#roadmap">read the roadmap</a>
        </div>
      </div>
      <div className="hero-stage" aria-label="EXP product preview">
        <ProductWindow />
        <div className="hero-platform" aria-label="macOS only, native Mac app">
          <i className="ph ph-desktop" aria-hidden="true" />
          <span>macOS only</span>
          <small>native Mac app</small>
        </div>
        <div className="stage-callout callout-one glass-medium">
          <span>canvas first</span>
          <strong>the work stays centered.</strong>
        </div>
        <div className="stage-callout callout-two glass-medium">
          <span>source components</span>
          <strong>references, not copies.</strong>
        </div>
      </div>
    </section>
  );
}

function WorkspaceCallout() {
  return (
    <section id="workspace" className="workspace-section" aria-labelledby="workspace-title">
      <div className="workspace-copy section-copy">
        <p className="section-label">multi-window mode</p>
        <h2 id="workspace-title">your workspace, your rules</h2>
        <p>
          you've got the space, who are we to tell you how to use it? want to
          spread out your workspace and menus across multiple monitors? we've got
          you. and easily toggle back to a single window view for when you're
          working from that coffee shop.
        </p>
        <ul className="workspace-points" aria-label="multi-window workspace benefits">
          <li>
            <strong>no hassle workspace toggle</strong>
            <span>seamlessly go from small screen to large screen(s) and back again.</span>
          </li>
          <li>
            <strong>you decide where things go</strong>
            <span>move, reorder, resize your menus and workspace to fit your workflow.</span>
          </li>
          <li>
            <strong>no more tab shufflin'</strong>
            <span>open all the tools you need side by side, as the design gods intended.</span>
          </li>
        </ul>
      </div>
      <figure className="workspace-visual bleed">
        <img
          src="/assets/exp-multi-monitor-workspace.png"
          alt="EXP design shown across two monitors, with the canvas on a wide display and detached panels on a vertical display"
        />
      </figure>
    </section>
  );
}

function FeatureStory() {
  const [active, setActive] = useState(featureMoments[0].id);
  const selected = featureMoments.find((feature) => feature.id === active) ?? featureMoments[0];

  return (
    <section id="features" className="features-section" aria-labelledby="features-title">
      <div className="feature-stage glass-medium glass-edge">
        <div className="feature-preview">
          <ProductWindow compact />
          <div className={`feature-lens ${selected.id}`}>
            <i className={`ph ${selected.icon}`} aria-hidden="true" />
          </div>
        </div>
        <div className="feature-copy">
          <p className="section-label">features</p>
          <h2 id="features-title">{selected.title}</h2>
          <p>{selected.line}</p>
          <p className="detail-line">{selected.detail}</p>
        </div>
      </div>
      <div className="feature-tabs" role="tablist" aria-label="feature moments">
        {featureMoments.map((feature) => (
          <button
            key={feature.id}
            type="button"
            role="tab"
            aria-selected={active === feature.id}
            className={active === feature.id ? "active" : ""}
            onClick={() => setActive(feature.id)}
          >
            <i className={`ph ${feature.icon}`} aria-hidden="true" />
            <span>{feature.title}</span>
          </button>
        ))}
      </div>
    </section>
  );
}

function SanaaCallout() {
  return (
    <section id="sanaa" className="sanaa-section" aria-labelledby="sanaa-title">
      <div className="sanaa-copy section-copy">
        <p className="section-label">meet Sanaa</p>
        <h2 id="sanaa-title">a design companion who can actually see the work.</h2>
        <p>
          Ask for a critique, another direction, or help with the repetitive bits.
          Sanaa reads the live canvas, grounds feedback in measured design facts,
          and keeps every suggestion connected to the layers it came from.
        </p>
        <ul className="feature-points" aria-label="Sanaa design companion benefits">
          <li>
            <strong>critique with receipts</strong>
            <span>Measured contrast, type, spacing, and target-size evidence sit beside thoughtful design observations—not vague AI vibes.</span>
          </li>
          <li>
            <strong>one click back to the canvas</strong>
            <span>Jump from a finding to the exact layer, or bring an idea into the composer to explore it further.</span>
          </li>
          <li>
            <strong>you stay the designer</strong>
            <span>Sanaa asks before changing existing work, uses small honest batches, and leaves each batch as one ordinary Undo step.</span>
          </li>
        </ul>
        <p className="sanaa-boundary">
          Uses your signed-in Codex account. EXP ships no model or API key, and Sanaa stays completely off until you enable her.
        </p>
      </div>
      <figure className="sanaa-gallery" aria-label="Sanaa critique report and Ask Sanaa menu inside EXP design">
        <div className="sanaa-shot report">
          <img
            src="/assets/sanaa-critique-report.png"
            alt="Sanaa's full critique report with numbered findings, measured gradient contrast, design observations, and buttons that locate exact canvas layers"
          />
        </div>
        <div className="sanaa-shot menu">
          <img
            src="/assets/sanaa-ask-menu.png"
            alt="EXP's Ask Sanaa menu offering critique, repetitive work, completion, variations, and design directions"
          />
        </div>
        <figcaption>ask from the canvas. inspect the evidence. decide what happens next.</figcaption>
      </figure>
    </section>
  );
}

function ComponentCallout() {
  return (
    <section id="component-system" className="component-section" aria-labelledby="component-title">
      <div className="component-copy section-copy">
        <p className="section-label">component system</p>
        <h2 id="component-title">components that stay understandable as they grow.</h2>
        <p>
          Build from a source, nest components inside components, and give each
          instance the state and overrides it actually needs. EXP keeps source
          identity, nested structure, public properties, and semantic meaning
          visible instead of hiding them behind a magic copy.
        </p>
        <ul className="feature-points" aria-label="component system benefits">
          <li>
            <strong>states belong to the component</strong>
            <span>Describe hover, focus, pressed, disabled, and custom variants without changing the shared default.</span>
          </li>
          <li>
            <strong>nest without losing your place</strong>
            <span>Every level keeps its own source, state, and stable override path—with cycle safety built in.</span>
          </li>
          <li>
            <strong>fork or detach on purpose</strong>
            <span>Duplicate a source for a new direction, or detach an instance while preserving the work you can see.</span>
          </li>
        </ul>
      </div>
      <figure className="component-gallery" aria-label="Nested components shown in EXP's component editor">
        <div className="component-shot overview">
          <img
            src="/assets/components-nested-overview.png"
            alt="EXP showing two component editors with nested layers, states, relationships, and component instances"
          />
        </div>
        <div className="component-shot detail">
          <img
            src="/assets/components-editor-detail.png"
            alt="A focused EXP component editor showing a selected nested component, its state, public properties, and overrides"
          />
        </div>
        <figcaption>see the full structure, then work at exactly the level you need.</figcaption>
      </figure>
    </section>
  );
}

function AccessibilityCallout() {
  return (
    <section id="accessibility" className="a11y-section" aria-labelledby="a11y-title">
      <div className="a11y-copy section-copy">
        <p className="section-label">accessibility</p>
        <h2 id="a11y-title">contrast checks belong where color decisions happen.</h2>
        <p>
          Never ship color on vibes alone. EXP shows WCAG contrast ratios and
          AA/fail feedback inside the color picker, because accessible design
          should be part of the workflow, not a last-minute add-on.
        </p>
      </div>
      <figure className="a11y-visual">
        <img
          src="/assets/a11y-contrast.png"
          alt="EXP color picker showing contrast ratios, AA status, and fail feedback"
        />
      </figure>
    </section>
  );
}

function AccessibilityCoreCallout() {
  return (
    <section className="a11y-core-section" aria-labelledby="a11y-core-title">
      <div className="section-copy">
        <p className="section-label">accessibility at the core</p>
        <h2 id="a11y-core-title">accessible thinking, in plain language.</h2>
        <p>
          EXP brings accessibility into the design conversation without making
          designers memorize a specification first. Friendly language explains
          what a role or relationship means, contextual guidance teaches the
          pattern, and the technical detail is still there when you need it.
        </p>
        <p className="a11y-boundary">
          EXP helps preserve good decisions; it does not claim that a design file
          can certify the accessibility of the finished product. Real code still
          needs keyboard, browser, and assistive-technology testing.
        </p>
      </div>
      <ul className="a11y-principles">
        <li>
          <i className="ph ph-chats-circle" aria-hidden="true" />
          <div><strong>guidance, not jargon</strong><span>Approachable labels, role-aware recommendations, and an in-app ARIA guide make the why easier to learn.</span></div>
        </li>
        <li>
          <i className="ph ph-tree-structure" aria-hidden="true" />
          <div><strong>meaning travels</strong><span>Roles, names, relationships, text intent, component states, and notes survive semantic handoff.</span></div>
        </li>
        <li>
          <i className="ph ph-keyboard" aria-hidden="true" />
          <div><strong>the app respects access needs too</strong><span>Keyboard and VoiceOver paths, system appearance, increased contrast, reduced motion, and reduced transparency are release checks.</span></div>
        </li>
      </ul>
      <div className="a11y-guide-gallery" aria-label="EXP ARIA guide screenshots">
        <figure>
          <img
            src="/assets/aria-guide-overview.png"
            alt="EXP ARIA Roles Guide introducing roles in plain language and organizing them by purpose"
          />
        </figure>
        <figure>
          <img
            src="/assets/aria-guide-role-detail.png"
            alt="EXP ARIA Roles Guide explaining the link role with when-to-use guidance, cautions, code, and common confusion"
          />
        </figure>
      </div>
    </section>
  );
}

function DesignLanguageCallout() {
  return (
    <section id="design-language" className="design-language-section" aria-labelledby="design-language-title">
      <div className="section-copy narrow">
        <p className="section-label">design language</p>
        <h2 id="design-language-title">build the system while you're building the work.</h2>
        <p>
          Save colors, gradients, and complete type styles; organize them into
          shared categories; browse them as a compact list or visual grid; and
          carry the same decisions into CSS, EXP JSON, or W3C design tokens.
        </p>
      </div>
      <div className="design-language-gallery" aria-label="Design language screenshots">
        <figure className="design-shot import">
          <img
            src="/assets/design-language-css-import.png"
            alt="EXP Design Language settings with a Paste Palette dialog ready to import CSS color variables"
          />
        </figure>
        <figure className="design-shot panel">
          <img
            src="/assets/design-language-panel-v2-1.png"
            alt="EXP Design Language panel showing colors, gradients, type styles, categories, recent items, and grid or list controls"
          />
        </figure>
      </div>
    </section>
  );
}

function ImportHandoffCallout() {
  const incoming = [
    "Figma REST",
    "Adobe XD",
    "local HTML + CSS",
    "static Storybook",
    "CodePen package",
    "PDF",
    "SVG + images",
  ];
  const outgoing = [
    "PNG / JPEG",
    "PDF / SVG",
    "semantic HTML",
    "design tokens",
    "Handoff Package",
    "CodePen Prefill",
    "local agent",
  ];

  return (
    <section id="import-handoff" className="import-handoff-section" aria-labelledby="import-handoff-title">
      <div className="section-copy">
        <p className="section-label">import + handoff</p>
        <h2 id="import-handoff-title">bring the work in. send the meaning onward.</h2>
        <p>
          Rescue an editable XD document, import a Figma file through its
          sanctioned API, or turn a local HTML page, static Storybook build, or
          CodePen export into editable canvas layers. When the design is ready,
          export pixels, vectors, semantic code, tokens, an inspectable package,
          a new CodePen, or let your own local agent read the work.
        </p>
        <p className="detail-line">
          EXP does not ask you to rebuild your process around the app. Use the
          format the next step needs, and keep moving.
        </p>
      </div>
      <figure className="handoff-map" aria-label="Import options flow into EXP design and then into several export and handoff options">
        <div className="handoff-column incoming">
          <span className="map-kicker">bring it in</span>
          {incoming.map((item) => <span key={item}>{item}</span>)}
        </div>
        <div className="handoff-arrow" aria-hidden="true"><i className="ph ph-arrow-right" /></div>
        <div className="handoff-core">
          <img src="/assets/exp-logo.png" alt="" />
          <strong>EXP<span>[design]</span></strong>
          <small>edit without losing the thread</small>
        </div>
        <div className="handoff-arrow" aria-hidden="true"><i className="ph ph-arrow-right" /></div>
        <div className="handoff-column outgoing">
          <span className="map-kicker">hand it onward</span>
          {outgoing.map((item) => <span key={item}>{item}</span>)}
        </div>
        <figcaption>your workflow stays yours.</figcaption>
      </figure>
    </section>
  );
}

function Roadmap() {
  const generatedDate = new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(siteContent.generatedAt));

  return (
    <section id="roadmap" className="roadmap-section" aria-labelledby="roadmap-title">
      <div className="roadmap-header">
        <div>
          <p className="section-label">living roadmap</p>
          <h2 id="roadmap-title">see the latest updates with the build.</h2>
        </div>
        <p>
          updates auto synced from <code>docs/ROADMAP.md</code> so there's no unanswered questions.
          last synced {generatedDate}.
        </p>
      </div>
      <ol className="roadmap-list">
        {siteContent.roadmap.map((item) => (
          <li key={item.title} className={item.status.replace(/[^a-z0-9]+/gi, "-")}>
            <span className="roadmap-status">{item.status}</span>
            <h3>{item.title}</h3>
            <p>{item.body}</p>
          </li>
        ))}
      </ol>
      <div className="sync-panels">
        <section className="sync-panel" aria-labelledby="progress-title">
          <div className="sync-panel-header">
            <p className="section-label">latest progress</p>
            <span>{siteContent.sourceFiles[0]}</span>
          </div>
          <h3 id="progress-title">{siteContent.progressLog[0]?.title}</h3>
          <p>{siteContent.progressLog[0]?.body}</p>
          <ul>
            {siteContent.progressLog.slice(1, 4).map((entry) => (
              <li key={`${entry.date}-${entry.title}`}>
                <span>{entry.date}</span>
                {entry.title}
              </li>
            ))}
          </ul>
        </section>
        <section className="sync-panel" aria-labelledby="queue-title">
          <div className="sync-panel-header">
            <p className="section-label">open queue</p>
            <span>{siteContent.counts.backlog.open} open</span>
          </div>
          <h3 id="queue-title">{siteContent.backlog[0]?.title}</h3>
          <p>{siteContent.backlog[0]?.detail}</p>
          <ul>
            {siteContent.backlog.slice(0, 3).map((item) => (
              <li key={item.id}>
                <span>{item.id}</span>
                {item.priority} · {item.area}
              </li>
            ))}
          </ul>
        </section>
      </div>
      <a className="roadmap-more" href="/download#tester-features">
        more detail on the download page
        <i className="ph ph-arrow-right" aria-hidden="true" />
      </a>
    </section>
  );
}

function SignupForm({
  id,
  source,
  buttonLabel = "request invite",
  idleMessage = "No spam. Just build notes and release notifications for EXP [design].",
  successMessage = "you are on the list. quiet little victory.",
  onSuccess,
}) {
  const [email, setEmail] = useState("");
  const [website, setWebsite] = useState("");
  const [status, setStatus] = useState("idle");
  const [message, setMessage] = useState(idleMessage);

  async function handleSubmit(event) {
    event.preventDefault();
    setStatus("submitting");
    setMessage("sending...");

    try {
      const response = await fetch("/api/signup", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, website, source }),
      });
      const result = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(result.error ?? "signup failed");
      }

      setStatus("success");
      setMessage(successMessage);
      setEmail("");
      onSuccess?.();
    } catch (error) {
      setStatus("error");
      setMessage(error.message || "something failed. try again in a minute.");
    }
  }

  return (
      <form className="invite-form" aria-label="tester release notification form" onSubmit={handleSubmit}>
        <label htmlFor={`${id}-email`}>email</label>
        <label className="visually-hidden" htmlFor={`${id}-website`}>website</label>
        <input
          className="signup-trap"
          id={`${id}-website`}
          type="text"
          tabIndex="-1"
          autoComplete="off"
          value={website}
          onChange={(event) => setWebsite(event.target.value)}
        />
        <div>
          <input
            id={`${id}-email`}
            type="email"
            placeholder="name@example.com"
            autoComplete="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            disabled={status === "submitting"}
          />
          <button type="submit" disabled={status === "submitting"}>
            {status === "submitting" ? "sending" : buttonLabel}
          </button>
        </div>
        <p className={`form-message ${status}`} role="status" aria-live="polite">
          {message}
        </p>
      </form>
  );
}

function TestingInvite() {
  return (
    <section id="testing" className="testing-section glass-thick glass-edge" aria-labelledby="testing-title">
      <div>
        <p className="section-label">testing</p>
        <h2 id="testing-title">want to help shape the next builds?</h2>
        <p>
          The download page now has the current build, install notes, reporting
          examples, known issues, and the release-notification signup in one
          place.
        </p>
      </div>
      <div className="testing-actions">
        <a className="button primary" href="/download">go to tester download</a>
        <a className="button secondary" href="/download#reporting">see reporting guide</a>
      </div>
    </section>
  );
}

const installSteps = [
  {
    title: "download the latest build",
    body: "Use the button on this page. GitHub opens the newest release; choose the EXP app file under Assets.",
    icon: "ph-download-simple",
  },
  {
    title: "unpack it",
    body: "If the file is a .zip, double-click it first. Then move EXP [design].app to Applications, or keep it in Downloads for a quick first pass.",
    icon: "ph-archive",
  },
  {
    title: "open with macOS in mind",
    body: "Early builds may show a security prompt. Control-click the app and choose Open, or use System Settings > Privacy & Security > Open Anyway.",
    icon: "ph-shield-check",
  },
  {
    title: "make a tiny test file",
    body: "Start with throwaway artboards before using real work. Save often and duplicate important .design files before opening them in a new build.",
    icon: "ph-file-plus",
  },
  {
    title: "send what you notice",
    body: "Bugs, rough edges, confusing labels, missing affordances, and moments where the tool gets in your way are all useful.",
    icon: "ph-chat-centered-text",
  },
];

const expectationCards = [
  {
    title: "this is product testing, not a polished launch",
    body: "Some paths will be unfinished, some copy will be temporary, and some behavior may change between builds. That is expected.",
  },
  {
    title: "small friction counts",
    body: "A bug is not only a crash. It can be a control that is hard to find, a value that feels wrong, a shortcut that surprises you, or a workflow that takes too many steps.",
  },
  {
    title: "your design instincts are the point",
    body: "You do not need to diagnose the code. Describe what you were trying to do, what happened, and what you expected instead.",
  },
];

const reportChecklist = [
  "what you were trying to do",
  "what happened instead",
  "steps to reproduce it, if you can repeat it",
  "a screenshot or short screen recording when visual",
  "your macOS version and the EXP build/version",
  "whether the .design file can be shared privately",
];

const staticKnownIssues = [
  {
    id: "SAFETY",
    title: "early builds are not for irreplaceable client files",
    priority: "important",
    detail: "Please test with duplicates or throwaway files. If something matters, keep a backup before opening it in a new tester build.",
  },
];

function DownloadHero() {
  return (
    <section id="top" className="download-hero">
      <div className="download-hero-copy">
        <h1>EXP [design] tester download</h1>
        <p>
          thanks for helping shape the app while it is still becoming itself.
          this page has the latest build path, install notes, what to expect,
          and what makes feedback useful.
        </p>
        <div className="hero-actions" aria-label="download actions">
          <a className="button primary" href="#download-signup">
            <i className="ph ph-download-simple" aria-hidden="true" />
            join list + download
          </a>
          <a className="button secondary" href="#reporting">
            how to report feedback
          </a>
        </div>
        <p className="download-note">
          EXP uses Sparkle for updates: it asks before enabling automatic checks,
          and Check for Updates… is always available from the app menu. The email
          list is only for EXP [design] product and release updates, and it will
          not be sold.
        </p>
      </div>
      <div className="download-preview" aria-label="EXP tester build preview">
        <ProductWindow />
        <div className="download-build-card glass-medium glass-edge">
          <span>tester build</span>
          <strong>macOS only</strong>
          <small>expect rough edges; save test files often.</small>
        </div>
      </div>
    </section>
  );
}

function DownloadSignup() {
  function openLatestReleaseSoon() {
    window.setTimeout(() => {
      window.location.href = releaseUrl;
    }, 650);
  }

  return (
    <section id="download-signup" className="download-signup glass-thick glass-edge" aria-labelledby="download-signup-title">
      <div>
        <p className="section-label">download</p>
        <h2 id="download-signup-title">get notified, then grab the latest build.</h2>
        <p>
          Sign up for release notes so new builds do not disappear into GitHub.
          The download opens after signup, and the release page stays public if
          you would rather skip the list.
        </p>
      </div>
      <div className="download-signup-panel">
        <SignupForm
          id="download-signup-form"
          source="download page"
          buttonLabel="join list + open GitHub"
          idleMessage="Build notifications only. No marketing list, no selling addresses."
          successMessage="you are on the release list. opening GitHub Releases..."
          onSuccess={openLatestReleaseSoon}
        />
        <a className="skip-download" href={releaseUrl} target="_blank" rel="noreferrer">
          skip email and open GitHub Releases
        </a>
      </div>
    </section>
  );
}

function InstallGuide() {
  return (
    <section id="install" className="download-section install-section" aria-labelledby="install-title">
      <div className="section-copy narrow">
        <p className="section-label">install</p>
        <h2 id="install-title">from download to first test file.</h2>
        <p>
          the install is intentionally ordinary for a Mac app, with one early-build caveat:
          macOS may ask you to confirm that you meant to open it.
        </p>
      </div>
      <ol className="install-list">
        {installSteps.map((step, index) => (
          <li key={step.title}>
            <span className="install-number">{String(index + 1).padStart(2, "0")}</span>
            <i className={`ph ${step.icon}`} aria-hidden="true" />
            <div>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}

function Expectations() {
  return (
    <section className="download-section expectations-section" aria-labelledby="expectations-title">
      <div className="section-copy">
        <p className="section-label">what to expect</p>
        <h2 id="expectations-title">use it like a designer, report it like a witness.</h2>
      </div>
      <div className="expectation-grid">
        {expectationCards.map((card) => (
          <article key={card.title} className="expectation-card">
            <h3>{card.title}</h3>
            <p>{card.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function ReportingGuide() {
  return (
    <section id="reporting" className="download-section reporting-section glass-thick glass-edge" aria-labelledby="reporting-title">
      <div className="section-copy">
        <p className="section-label">reporting</p>
        <h2 id="reporting-title">a useful report is just enough context to find the thread.</h2>
        <p>
          best path: use <strong>Help &gt; Send Feedback</strong> inside the app. if the app will not open,
          use GitHub instead.
        </p>
        <div className="hero-actions">
          <a className="button primary" href={issuesUrl} target="_blank" rel="noreferrer">
            <i className="ph ph-bug" aria-hidden="true" />
            report on GitHub
          </a>
          <a className="button secondary" href={releasesUrl} target="_blank" rel="noreferrer">
            view all releases
          </a>
        </div>
      </div>
      <div className="report-panels">
        <section className="report-card" aria-labelledby="bug-example-title">
          <p className="section-label">example bug</p>
          <h3 id="bug-example-title">valuable bug report</h3>
          <dl>
            <div>
              <dt>trying to</dt>
              <dd>resize a selected text box after changing line height.</dd>
            </div>
            <div>
              <dt>expected</dt>
              <dd>the box keeps the new line height and resizes from the handle.</dd>
            </div>
            <div>
              <dt>actually</dt>
              <dd>the line height resets after I click away, then the box crops the second line.</dd>
            </div>
            <div>
              <dt>repeat</dt>
              <dd>new text box &gt; set line height to 1.8 &gt; drag lower-right handle &gt; click the canvas.</dd>
            </div>
          </dl>
        </section>
        <section className="report-card" aria-labelledby="idea-example-title">
          <p className="section-label">example idea</p>
          <h3 id="idea-example-title">valuable improvement request</h3>
          <p>
            "When I am arranging many artboards, I keep wanting a quick way to zoom out to the full wall,
            then return to the board I was editing. The current fit/actual shortcuts help, but I lose my place."
          </p>
          <ul>
            {reportChecklist.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </section>
      </div>
    </section>
  );
}

function TesterFeatures() {
  return (
    <section id="tester-features" className="download-section tester-features" aria-labelledby="tester-features-title">
      <div className="roadmap-header">
        <div>
          <p className="section-label">what is ready to try</p>
          <h2 id="tester-features-title">the roadmap, translated for testing.</h2>
        </div>
        <p>
          pulled from <code>docs/ROADMAP.md</code>, then rewritten around what a designer can actually try in the app.
        </p>
      </div>
      <div className="tester-feature-list">
        {siteContent.testerFeatures.map((feature) => (
          <article key={feature.phase} className={feature.status.replace(/[^a-z0-9]+/gi, "-")}>
            <span>{feature.status}</span>
            <h3>{feature.title}</h3>
            <p>{feature.body}</p>
            <small>{feature.phase}</small>
          </article>
        ))}
      </div>
    </section>
  );
}

function KnownIssues() {
  const issues = [...staticKnownIssues, ...(siteContent.testerKnownIssues ?? [])];

  return (
    <section id="known-issues" className="download-section known-issues" aria-labelledby="known-issues-title">
      <div className="section-copy narrow">
        <p className="section-label">known issues</p>
        <h2 id="known-issues-title">rough edges worth knowing before you start.</h2>
        <p>
          these are not meant to scare you off. they are here so you can test with context and avoid losing time to known behavior.
        </p>
      </div>
      <div className="issue-list">
        {issues.map((issue) => (
          <article key={`${issue.id}-${issue.title}`} className="issue-card">
            <div>
              <span>{issue.id}</span>
              <strong>{issue.priority}</strong>
            </div>
            <h3>{issue.title}</h3>
            <p>{issue.detail}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function TesterFooterCta() {
  return (
    <section className="download-final glass-thick glass-edge" aria-labelledby="final-download-title">
      <div>
        <p className="section-label">ready</p>
        <h2 id="final-download-title">grab the build, make a small mess, tell me where it snagged.</h2>
      </div>
      <a className="button primary" href="#download-signup">
        <i className="ph ph-download-simple" aria-hidden="true" />
        join list + download
      </a>
    </section>
  );
}

function DownloadPage() {
  const progress = useScrollProgress();

  useEffect(() => {
    document.title = "EXP [design] tester download";
    document
      .querySelector("meta[name='description']")
      ?.setAttribute(
        "content",
        "Download the latest EXP [design] tester build, install it on macOS, and learn how to report useful bugs and product feedback.",
      );
  }, []);

  return (
    <>
      <Header
        progress={progress}
        actionLabel="get the build"
        actionHref="#download-signup"
        brandHref="/"
      />
      <main>
        <DownloadHero />
        <DownloadSignup />
        <InstallGuide />
        <Expectations />
        <ReportingGuide />
        <TesterFeatures />
        <KnownIssues />
        <TesterFooterCta />
      </main>
      <Footer />
    </>
  );
}

function Footer() {
  // Plain, always-visible links to every page the header dropdowns jump to.
  // This is the fallback path: if a dropdown ever fails to open (JS error,
  // motor/pointer difficulty, reduced-motion edge case, whatever), every
  // subpage is still one direct click away here.
  return (
    <footer className="site-footer">
      <a className="brand-lockup" href="#top" aria-label="EXP [design] home">
        <img src="/assets/exp-logo.png" alt="" />
        <span>EXP<span>[design]</span></span>
      </a>
      <p>native macOS. quiet precision. source, never master.</p>
      <nav className="footer-sitemap" aria-label="site pages">
        <div>
          <p className="footer-sitemap-heading">features</p>
          {featureLinks.map((link) => (
            <a key={link.href} href={link.href}>
              {link.label}
            </a>
          ))}
        </div>
        <div>
          <p className="footer-sitemap-heading">learn</p>
          {learnLinks.map((link) => (
            <a key={link.href} href={link.href}>
              {link.label}
            </a>
          ))}
        </div>
        <div>
          <p className="footer-sitemap-heading">more</p>
          <a href="/#roadmap">roadmap</a>
          <a href="/download">download</a>
        </div>
      </nav>
    </footer>
  );
}

function HelpCard({ article, compact = false }) {
  return (
    <a className={compact ? "help-card compact" : "help-card"} href={`/learn/${article.slug}`}>
      {!compact && (
        <span className="help-card-image">
          <img src={article.cardPoster} alt="" loading="lazy" />
        </span>
      )}
      <span className="help-card-copy">
        <span className="help-card-kicker">{article.category}</span>
        <strong>{article.title}</strong>
        <span>{article.summary}</span>
        <small>{article.readTime} · {article.sections.filter((section) => section.video).length} visual {article.sections.filter((section) => section.video).length === 1 ? "guide" : "guides"}</small>
      </span>
      <i className="ph ph-arrow-up-right" aria-hidden="true" />
    </a>
  );
}

function HelpVideo({ video }) {
  const ref = React.useRef(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) return undefined;

    const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (motionQuery.matches) return undefined;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          node.play().catch(() => {});
        } else {
          node.pause();
        }
      },
      { threshold: 0.55 },
    );

    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return (
    <figure className="help-video">
      <video
        ref={ref}
        controls
        loop
        muted
        playsInline
        preload="metadata"
        poster={video.poster}
        aria-label={video.label}
      >
        <source src={video.src} type="video/mp4" />
        Your browser does not support embedded video.
      </video>
      <figcaption>
        <i className="ph ph-play-circle" aria-hidden="true" />
        <span>{video.label}</span>
      </figcaption>
    </figure>
  );
}

function LearnPage() {
  const progress = useScrollProgress();
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("all");

  const filtered = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    return helpArticles.filter((article) => {
      const categoryMatch = category === "all" || article.category === category;
      const textMatch = !normalized || searchableHelpText(article).includes(normalized);
      return categoryMatch && textMatch;
    });
  }, [category, query]);

  useEffect(() => {
    document.title = "EXP [design] — Help";
    document
      .querySelector("meta[name='description']")
      ?.setAttribute(
        "content",
        "Searchable written tutorials and short visual guides for EXP [design] on macOS.",
      );
  }, []);

  return (
    <>
      <Header
        progress={progress}
        actionLabel="get the build"
        actionHref="/download#download-signup"
        brandHref="/"
      />
      <main>
        <section id="top" className="help-hero">
          <div className="section-copy">
            <p className="section-label">EXP Help</p>
            <h1>find the small thing you’re trying to do.</h1>
            <p>
              Written steps for searching and scanning, with quiet visual guides
              when seeing the action is easier than describing it.
            </p>
          </div>
          <form className="help-search" role="search" onSubmit={(event) => event.preventDefault()}>
            <label htmlFor="help-query">Search Help</label>
            <span className="help-search-field">
              <i className="ph ph-magnifying-glass" aria-hidden="true" />
              <input
                id="help-query"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Try “duplicate,” “center,” or “grid”"
                autoComplete="off"
              />
              {query && (
                <button type="button" onClick={() => setQuery("")} aria-label="Clear Help search">
                  <i className="ph ph-x" aria-hidden="true" />
                </button>
              )}
            </span>
          </form>
        </section>

        <section className="help-library" aria-labelledby="help-library-title">
          <div className="help-library-head">
            <div>
              <p className="section-label">task library</p>
              <h2 id="help-library-title">Start with what you need now.</h2>
            </div>
            <p aria-live="polite">{filtered.length} {filtered.length === 1 ? "tutorial" : "tutorials"}</p>
          </div>

          <div className="help-filters" aria-label="Filter tutorials by category">
            {["all", ...helpCategories].map((item) => (
              <button
                key={item}
                type="button"
                className={category === item ? "active" : ""}
                aria-pressed={category === item}
                onClick={() => setCategory(item)}
              >
                {item}
              </button>
            ))}
          </div>

          {filtered.length > 0 ? (
            <div className="help-grid">
              {filtered.map((article) => <HelpCard key={article.slug} article={article} />)}
            </div>
          ) : (
            <div className="help-no-results">
              <i className="ph ph-binoculars" aria-hidden="true" />
              <h3>No tutorial matches that yet.</h3>
              <p>Try a shorter term, or clear the category filter.</p>
              <button type="button" onClick={() => { setQuery(""); setCategory("all"); }}>
                Show every tutorial
              </button>
            </div>
          )}
        </section>
      </main>
      <Footer />
    </>
  );
}

function HelpArticlePage({ article }) {
  const progress = useScrollProgress();
  const related = article.related.map(findHelpArticle).filter(Boolean);

  useEffect(() => {
    document.title = `${article.title} — EXP Help`;
    document
      .querySelector("meta[name='description']")
      ?.setAttribute("content", article.summary);
  }, [article]);

  return (
    <>
      <Header
        progress={progress}
        actionLabel="all help"
        actionHref="/learn"
        brandHref="/"
      />
      <main className="help-article-page">
        <header className="help-article-hero">
          <nav aria-label="Breadcrumb">
            <a href="/learn">Help</a>
            <i className="ph ph-caret-right" aria-hidden="true" />
            <span>{article.category}</span>
          </nav>
          <p className="section-label">{article.category}</p>
          <h1>{article.title}</h1>
          <p className="help-article-summary">{article.summary}</p>
          <p className="help-article-meta">{article.readTime} · Updated {article.updated}</p>
        </header>

        <div className="help-article-layout">
          <aside className="help-toc" aria-label="On this page">
            <strong>On this page</strong>
            {article.sections.map((section) => (
              <a key={section.id} href={`#${section.id}`}>{section.title}</a>
            ))}
          </aside>

          <article className="help-article-body">
            {article.sections.map((section) => (
              <section key={section.id} id={section.id}>
                <h2>{section.title}</h2>
                {section.paragraphs?.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
                {section.steps && (
                  <ol>
                    {section.steps.map((step) => <li key={step}>{step}</li>)}
                  </ol>
                )}
                {section.note && (
                  <aside className="help-note">
                    <i className="ph ph-info" aria-hidden="true" />
                    <p>{section.note}</p>
                  </aside>
                )}
                {section.video && <HelpVideo video={section.video} />}
              </section>
            ))}
          </article>
        </div>

        <section className="help-related" aria-labelledby="help-related-title">
          <p className="section-label">keep going</p>
          <h2 id="help-related-title">Related tutorials</h2>
          <div className="help-related-grid">
            {related.map((item) => <HelpCard key={item.slug} article={item} compact />)}
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}

export default function App() {
  const progress = useScrollProgress();
  const path = window.location.pathname.replace(/\/$/, "") || "/";

  // Cross-page jump links (e.g. /#features from /download) arrive as a full
  // navigation, so the browser tries to scroll to the hash before React has
  // rendered the target section. Re-run the scroll after mount, once the
  // section exists. (Same-page hash clicks scroll natively and skip this.)
  useEffect(() => {
    const hash = window.location.hash;
    if (!hash) return undefined;
    let raf = requestAnimationFrame(() => {
      raf = requestAnimationFrame(() => {
        document.querySelector(hash)?.scrollIntoView({ block: "start" });
      });
    });
    return () => cancelAnimationFrame(raf);
  }, []);

  if (path === "/download") {
    return <DownloadPage />;
  }

  if (path === "/learn") {
    return <LearnPage />;
  }

  if (path.startsWith("/learn/")) {
    const article = findHelpArticle(path.slice("/learn/".length));
    if (article) return <HelpArticlePage article={article} />;
    return <LearnPage />;
  }

  return (
    <>
      <Header progress={progress} />
      <main>
        <Hero />
        <FeatureStory />
        <SanaaCallout />
        <ComponentCallout />
        <WorkspaceCallout />
        <AccessibilityCallout />
        <AccessibilityCoreCallout />
        <DesignLanguageCallout />
        <ImportHandoffCallout />
        <Roadmap />
        <TestingInvite />
      </main>
      <Footer />
    </>
  );
}
