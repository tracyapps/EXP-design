import React, { useEffect, useMemo, useState } from "react";
import siteContent from "./generated/siteContent.json";

const navItems = [
  { label: "features", href: "#features" },
  { label: "field guide", href: "#field-guide" },
  { label: "roadmap", href: "#roadmap" },
  { label: "testing", href: "#testing" },
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

function Header({ progress }) {
  return (
    <header className="site-header glass-thin glass-edge">
      <a className="brand-lockup" href="#top" aria-label="EXP [design] home">
        <img src="/assets/exp-logo.png" alt="" />
        <span>EXP<span>[design]</span></span>
      </a>
      <nav aria-label="primary">
        {navItems.map((item) => (
          <a key={item.href} href={item.href}>
            {item.label}
          </a>
        ))}
      </nav>
      <a className="header-action" href="#testing">
        follow the build
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
          <li key={item.title} className={item.status.replace(" ", "-")}>
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
