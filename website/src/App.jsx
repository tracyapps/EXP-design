import React, { useEffect, useMemo, useState } from "react";
import siteContent from "./generated/siteContent.json";

const releaseUrl = "https://github.com/tracyapps/EXP-design/releases/latest";
const releasesUrl = "https://github.com/tracyapps/EXP-design/releases";
const issuesUrl = "https://github.com/tracyapps/EXP-design/issues/new";

// One nav for every page. Feature callouts live on the homepage; the dropdown
// jump-links to them with absolute /#anchor hrefs so they also work from
// /download and /learn.
const featureLinks = [
  { label: "features", href: "/#features" },
  { label: "accessibility", href: "/#accessibility" },
  { label: "design language", href: "/#design-language" },
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
    title: "source components",
    icon: "ph-stack",
    line: "instances point back to a source, with bounded overrides for text, fill, and visibility.",
    detail: "no mystery copies. edit the source, return, and every instance updates.",
  },
  {
    id: "notes",
    title: "handoff notes",
    icon: "ph-note-pencil",
    line: "notes live on the artboard, move with it, duplicate with it, and can export into PDF handoff pages.",
    detail: "assumptions, test-first prompts, and context travel with the thing they explain.",
  },
];

const guideRows = [
  {
    title: "set up a working wall",
    time: "soon",
    body: "coming soon: a short walkthrough for artboards, presets, rearranging work, and keeping the canvas open.",
  },
  {
    title: "make a source component",
    time: "soon",
    body: "coming soon: a practical component guide covering sources, instances, overrides, and detach.",
  },
  {
    title: "write notes that matter",
    time: "soon",
    body: "coming soon: a field note pattern for assumptions, testing prompts, and handoff context.",
  },
  {
    title: "export a handoff package",
    time: "soon",
    body: "coming soon: the small export checklist for PNG, PDF, SVG, and notes pages.",
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

  useEffect(() => {
    if (!open) return undefined;
    function onPointerDown(event) {
      if (ref.current && !ref.current.contains(event.target)) setOpen(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open]);

  return (
    <div
      className={open ? "nav-dropdown open" : "nav-dropdown"}
      ref={ref}
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
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
      <img src="/assets/exp-canvas-workbench.png" alt="EXP design app canvas with layers, artboards, and properties panels" />
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
          fast canvas work, source components, and handoff notes that travel with
          the artboard.
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

function DesignLanguageCallout() {
  return (
    <section id="design-language" className="design-language-section" aria-labelledby="design-language-title">
      <div className="section-copy narrow">
        <p className="section-label">in progress</p>
        <h2 id="design-language-title">a design language panel is starting to take shape.</h2>
        <p>
          Save colors and gradients, name them, sort them into categories, and
          switch between swatch and list views while a system is still forming.
        </p>
      </div>
      <div className="design-language-gallery" aria-label="Design language screenshots">
        <figure className="design-shot settings">
          <img
            src="/assets/design-language-settings.png"
            alt="EXP settings window showing design language color and gradient categories"
          />
        </figure>
        <figure className="design-shot list">
          <img
            src="/assets/design-language-list.png"
            alt="EXP design language panel in list view with named colors and gradients"
          />
        </figure>
        <figure className="design-shot grid">
          <img
            src="/assets/design-language-grid.png"
            alt="EXP design language panel in swatch grid view"
          />
        </figure>
      </div>
    </section>
  );
}

function FieldGuide() {
  const [open, setOpen] = useState(0);

  return (
    <section id="field-guide" className="guide-section" aria-labelledby="guide-title">
      <div className="section-copy narrow">
        <p className="section-label">field guide</p>
        <h2 id="guide-title">how-to material for people actually testing it.</h2>
        <p>
          short, direct walkthroughs are coming soon. the first pass will focus
          on the things testers need to try the app without a tour guide hovering
          nearby.
        </p>
      </div>
      <div className="guide-list">
        {guideRows.map((row, index) => (
          <button
            key={row.title}
            type="button"
            className={open === index ? "guide-row open" : "guide-row"}
            aria-expanded={open === index}
            onClick={() => setOpen(open === index ? -1 : index)}
          >
            <span className="guide-index">{String(index + 1).padStart(2, "0")}</span>
              <span className="guide-main">
                <strong>{row.title}</strong>
              <span>{open === index ? row.body : "coming soon"}</span>
            </span>
            <span className="guide-time">{row.time}</span>
          </button>
        ))}
      </div>
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
          There is no auto-updater yet. The email list is only for EXP [design]
          product and release updates, and it will not be sold.
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
  return (
    <footer className="site-footer">
      <a className="brand-lockup" href="#top" aria-label="EXP [design] home">
        <img src="/assets/exp-logo.png" alt="" />
        <span>EXP<span>[design]</span></span>
      </a>
      <p>native macOS. quiet precision. source, never master.</p>
    </footer>
  );
}

function youtubeId(url) {
  if (!url) return "";
  const match = url.match(/(?:youtu\.be\/|v=|embed\/)([\w-]{6,})/);
  return match ? match[1] : "";
}

function VideoCard({ video }) {
  const id = youtubeId(video.youtubeUrl);
  const thumb = video.thumbnail || (id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "");
  const ready = Boolean(video.youtubeUrl);

  return (
    <a
      className={ready ? "video-card" : "video-card pending"}
      href={ready ? video.youtubeUrl : undefined}
      target={ready ? "_blank" : undefined}
      rel={ready ? "noreferrer" : undefined}
      aria-disabled={ready ? undefined : "true"}
    >
      <span className="video-thumb">
        {thumb ? (
          <img src={thumb} alt="" loading="lazy" />
        ) : (
          <span className="video-thumb-empty" aria-hidden="true" />
        )}
        <span className="video-play" aria-hidden="true">
          <i className="ph ph-play-fill" />
        </span>
        {video.duration && <span className="video-duration">{video.duration}</span>}
      </span>
      <span className="video-meta">
        {video.category && <span className="video-tag">{video.category}</span>}
        <strong>{video.title}</strong>
        <span>{ready ? video.description : "coming soon"}</span>
      </span>
    </a>
  );
}

function LearnPage() {
  const progress = useScrollProgress();
  const videos = siteContent.learnVideos ?? [];
  const readyCount = videos.filter((video) => video.youtubeUrl).length;

  useEffect(() => {
    document.title = "EXP [design] — learn";
    document
      .querySelector("meta[name='description']")
      ?.setAttribute(
        "content",
        "Short walkthroughs and tutorials for testing EXP [design] on macOS.",
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
        <section id="top" className="learn-hero">
          <div className="section-copy">
            <p className="section-label">learn</p>
            <h1>short walkthroughs for people actually testing it.</h1>
            <p>
              quick, practical videos — no tour guide hovering nearby. more are on
              the way; the list fills in as they publish.
            </p>
          </div>
        </section>
        {videos.length > 0 && (
          <section className="learn-videos" aria-label="tutorial videos">
            {readyCount === 0 && (
              <p className="learn-empty">
                the first videos are being recorded now. in the meantime, the written
                walkthroughs below cover the essentials.
              </p>
            )}
            <div className="learn-grid">
              {videos.map((video) => (
                <VideoCard key={video.id ?? video.title} video={video} />
              ))}
            </div>
          </section>
        )}
        <FieldGuide />
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

  return (
    <>
      <Header progress={progress} />
      <main>
        <Hero />
        <FeatureStory />
        <WorkspaceCallout />
        <AccessibilityCallout />
        <DesignLanguageCallout />
        <Roadmap />
        <TestingInvite />
      </main>
      <Footer />
    </>
  );
}
