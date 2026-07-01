// TopBar — the macOS title bar: traffic lights · document name · centered
// new-artboard control · right system cluster (zoom, panel toggles, workspace,
// appearance). Cosmetic recreation of MainWindow's toolbar.
const NS = window.EXPDesignDesignSystem_fb82b2;

function TrafficLights() {
  const dots = [["#ff5f57", "#e0443e"], ["#febc2e", "#d89e24"], ["#28c840", "#1aab29"]];
  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
      {dots.map(([a, b], i) => (
        <span key={i} style={{ width: 12, height: 12, borderRadius: 999,
          background: a, boxShadow: `inset 0 0 0 0.5px ${b}` }} />
      ))}
    </div>
  );
}

function TopBar({ doc, zoom, setZoom, appearance, setAppearance, panels, setPanels }) {
  const { IconButton, Tooltip } = NS;
  return (
    <div className="glass-thin" style={{
      height: "var(--titlebar-height)", display: "flex", alignItems: "center",
      padding: "0 16px", gap: 16, borderBottom: "1px solid var(--hairline)",
      flex: "none", position: "relative", zIndex: 5,
    }}>
      <TrafficLights />

      <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.15, marginLeft: 4 }}>
        <span style={{ fontSize: 13, fontWeight: "var(--w-medium)", color: "var(--text-primary)" }}>
          {doc.docName}<span style={{ color: "var(--text-tertiary)", fontWeight: "var(--w-light)" }}>.design</span>
        </span>
        <span style={{ fontSize: 10, color: "var(--text-tertiary)", fontWeight: "var(--w-light)" }}>Edited</span>
      </div>

      {/* centered new-artboard control */}
      <div style={{ position: "absolute", left: "50%", transform: "translateX(-50%)",
        display: "flex", alignItems: "center", height: 28, borderRadius: 8,
        background: "var(--surface-field)", border: "1px solid var(--border-glass)",
        boxShadow: "var(--glass-inner-hi)" }}>
        <button style={iconTrigger}><i className="ph-bold ph-plus" style={{ fontSize: 14 }} /></button>
        <span style={{ width: 1, height: 16, background: "var(--hairline)" }} />
        <button style={iconTrigger}><i className="ph-bold ph-caret-down" style={{ fontSize: 11 }} /></button>
      </div>

      <div style={{ flex: 1 }} />

      {/* right system cluster */}
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        <IconButton icon="magnifying-glass-minus" title="Zoom out" onClick={() => setZoom(Math.max(5, zoom - 10))} />
        <span style={{ width: 34, textAlign: "center", fontSize: 12, fontVariantNumeric: "tabular-nums",
          color: "var(--text-primary)" }}>{zoom}</span>
        <IconButton icon="magnifying-glass-plus" title="Zoom in" onClick={() => setZoom(Math.min(400, zoom + 10))} />
        <IconButton icon="arrows-out-simple" title="Zoom presets" />
        <span style={{ width: 1, height: 16, background: "var(--hairline)", margin: "0 6px" }} />
        <IconButton icon="sidebar-simple" active={panels.left} title="Left panel"
          onClick={() => setPanels({ ...panels, left: !panels.left })} />
        <IconButton icon="sidebar-simple" active={panels.right} title="Right panel"
          style={{ transform: "scaleX(-1)" }} onClick={() => setPanels({ ...panels, right: !panels.right })} />
        <span style={{ width: 1, height: 16, background: "var(--hairline)", margin: "0 6px" }} />
        <Tooltip label={appearance === "exp-dark" ? "Light appearance" : "Dark appearance"} side="bottom">
          <IconButton icon={appearance === "exp-dark" ? "sun" : "moon"}
            onClick={() => setAppearance(appearance === "exp-dark" ? "exp-light" : "exp-dark")} title="Appearance" />
        </Tooltip>
      </div>
    </div>
  );
}

const iconTrigger = {
  width: 30, height: 28, display: "inline-flex", alignItems: "center", justifyContent: "center",
  background: "none", border: "none", cursor: "pointer", color: "var(--text-primary)",
};

window.TopBar = TopBar;
