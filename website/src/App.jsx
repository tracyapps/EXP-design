import React, { useEffect, useMemo, useState } from "react";
import siteContent from "./generated/siteContent.json";

const releaseUrl = "https://github.com/tracyapps/EXP-design/releases/latest";
const releasesUrl = "https://github.com/tracyapps/EXP-design/releases";
const issuesUrl = "https://github.com/tracyapps/EXP-design/issues/new";

const navItems = [
  { label: "features", href: "#features" },
  { label: "field guide", href: "#field-guide" },
  { label: "roadmap", href: "#roadmap" },
  { label: "testing", href: "#testing" },
];

const downloadNavItems = [
  { label: "install", href: "#install" },
  { label: "reporting", href: "#reporting" },
  { label: "features", href: "#tester-features" },
  { label: "known issues", href: "#known-issues" },
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

function Header({
  progress,
  items = navItems,
  actionLabel = "follow the build",
  actionHref = "#testing",
  brandHref = "#top",
}) {
  return (
    <header className="site-header glass-thin glass-edge">
      <a className="brand-lockup" href={brandHref} aria-label="EXP [design] home">
        <img src="/assets/exp-logo.png" alt="" />
        <span>EXP<span>[design]</span></span>
      </a>
      <nav aria-label="primary">
        {items.map((item) => (
          <a key={item.href} href={item.href}>
            {item.label}
          </a>
        ))}
      </nav>
      <a className="header-action" href={actionHref}>
        {actionLabel}
      </a>
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
          <a className="button primary" href="#testing">follow the build</a>
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

function ProductStory() {
  return (
    <section className="product-story" aria-labelledby="story-title">
      <div className="section-copy">
        <p className="section-label">product surface</p>
        <h2 id="story-title">made for the part where design is still thinking.</h2>
        <p>
          EXP does not try to be everything. it keeps the high-frequency workflow
          close: artboards, layers, source components, precise export, and notes
          that make handoff less performative.
        </p>
      </div>
      <div className="story-rail">
        <div className="rail-line" />
        <div className="rail-pin pin-a">pan</div>
        <div className="rail-pin pin-b">zoom</div>
        <div className="rail-pin pin-c">handoff</div>
      </div>
    </section>
  );
}

function WorkspaceCallout() {
  return (
    <section id="workspace" className="workspace-section" aria-labelledby="workspace-title">
      <div className="workspace-copy section-copy">
        <p className="section-label">multi-window mode</p>
        <h2 id="workspace-title">you've got the space. who are we to tell you how to use it?</h2>
        <p>
          when your desk has real display real estate, EXP lets the app breathe:
          keep the canvas wide open, move panels to another monitor, and stop
          treating a vertical screen like an expensive sidebar.
        </p>
        <ul className="workspace-points" aria-label="multi-window workspace benefits">
          <li>
            <strong>canvas where the work is</strong>
            <span>give the wall the big display and keep artboards in view.</span>
          </li>
          <li>
            <strong>panels where they belong</strong>
            <span>layers, components, and properties can live on their own screen.</span>
          </li>
          <li>
            <strong>no forced tab shuffle</strong>
            <span>open the tools you need side by side, as the design gods intended.</span>
          </li>
        </ul>
      </div>
      <figure className="workspace-visual glass-medium glass-edge">
        <img
          src="/assets/exp-multi-monitor-workspace.png"
          alt="EXP design shown across two monitors, with the canvas on a wide display and detached panels on a vertical display"
        />
        <figcaption>canvas on the big display. palettes on the vertical one. finally.</figcaption>
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
    </section>
  );
}

function TestingInvite() {
  const [email, setEmail] = useState("");
  const [website, setWebsite] = useState("");
  const [status, setStatus] = useState("idle");
  const [message, setMessage] = useState("no spam. just build notes, testing invites, and eventual download news.");

  async function handleSubmit(event) {
    event.preventDefault();
    setStatus("submitting");
    setMessage("sending...");

    try {
      const response = await fetch("/api/signup", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, website, source: "testing invite" }),
      });
      const result = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(result.error ?? "signup failed");
      }

      setStatus("success");
      setMessage("you are on the list. quiet little victory.");
      setEmail("");
    } catch (error) {
      setStatus("error");
      setMessage(error.message || "something failed. try again in a minute.");
    }
  }

  return (
    <section id="testing" className="testing-section glass-thick glass-edge" aria-labelledby="testing-title">
      <div>
        <p className="section-label">testing</p>
        <h2 id="testing-title">built in the open, before it is a product.</h2>
        <p>
          for now, this is a place to follow progress, onboard design friends,
          and document what needs testing. when packaging is ready, the same
          surface can become the download and release-note home.
        </p>
      </div>
      <form className="invite-form" aria-label="tester interest form" onSubmit={handleSubmit}>
        <label htmlFor="tester-email">tester email</label>
        <label className="visually-hidden" htmlFor="tester-website">website</label>
        <input
          className="signup-trap"
          id="tester-website"
          type="text"
          tabIndex="-1"
          autoComplete="off"
          value={website}
          onChange={(event) => setWebsite(event.target.value)}
        />
        <div>
          <input
            id="tester-email"
            type="email"
            placeholder="name@example.com"
            autoComplete="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            disabled={status === "submitting"}
          />
          <button type="submit" disabled={status === "submitting"}>
            {status === "submitting" ? "sending" : "request invite"}
          </button>
        </div>
        <p className={`form-message ${status}`} role="status" aria-live="polite">
          {message}
        </p>
      </form>
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
    id: "TEXT",
    title: "text styling can be lost on direct click-out",
    priority: "known",
    detail: "If you style selected text from the Inspector and click straight off the text box, the change can be dropped. Workaround: click once inside the text to collapse the selection, then click out.",
  },
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
          thanks for helping shape the app while it is still becoming itself. this page has
          the latest build link, install notes, what to expect, and what makes feedback useful.
        </p>
        <div className="hero-actions" aria-label="download actions">
          <a className="button primary" href={releaseUrl} target="_blank" rel="noreferrer">
            <i className="ph ph-download-simple" aria-hidden="true" />
            download latest build
          </a>
          <a className="button secondary" href="#reporting">
            how to report feedback
          </a>
        </div>
        <p className="download-note">
          downloads are hosted on GitHub Releases. the primary link always opens the newest available build.
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
      <a className="button primary" href={releaseUrl} target="_blank" rel="noreferrer">
        <i className="ph ph-download-simple" aria-hidden="true" />
        download latest build
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
        items={downloadNavItems}
        actionLabel="download"
        actionHref={releaseUrl}
        brandHref="#top"
      />
      <main>
        <DownloadHero />
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

export default function App() {
  const progress = useScrollProgress();
  const path = window.location.pathname.replace(/\/$/, "") || "/";

  if (path === "/download") {
    return <DownloadPage />;
  }

  return (
    <>
      <Header progress={progress} />
      <main>
        <Hero />
        <ProductStory />
        <WorkspaceCallout />
        <FeatureStory />
        <FieldGuide />
        <Roadmap />
        <TestingInvite />
      </main>
      <Footer />
    </>
  );
}
