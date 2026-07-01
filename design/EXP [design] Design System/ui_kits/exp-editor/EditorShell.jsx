// EditorShell — composes the whole three-pane editor and owns the interactive
// state (tool, selection, zoom, appearance, panel visibility).
const NS = window.EXPDesignDesignSystem_fb82b2;

function EditorShell() {
  const { ToolStrip } = NS;
  const [doc, setDoc] = React.useState(window.EXP_DOC);
  const [tool, setTool] = React.useState("select");
  const [selected, setSelected] = React.useState("c1");
  const [zoom, setZoom] = React.useState(window.EXP_DOC.zoom);
  const [appearance, setAppearance] = React.useState("exp-dark");
  const [panels, setPanels] = React.useState({ left: true, right: true });

  React.useEffect(() => {
    document.documentElement.className = appearance;
  }, [appearance]);

  const update = (patch) => {
    setDoc((d) => ({
      ...d,
      layers: d.layers.map((l) => (l.id === selected ? { ...l, ...patch } : l)),
    }));
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh",
      background: "var(--surface-window)", overflow: "hidden" }}>
      <window.TopBar doc={doc} zoom={zoom} setZoom={setZoom}
        appearance={appearance} setAppearance={setAppearance}
        panels={panels} setPanels={setPanels} />

      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        <ToolStrip active={tool} onSelect={setTool} />

        {panels.left && (
          <div style={{ width: "var(--dock-left-width)", flex: "none", padding: 10,
            borderRight: "1px solid var(--hairline)", background: "var(--surface-window)" }}>
            <window.LayersPanel doc={doc} selected={selected} onSelect={setSelected} />
          </div>
        )}

        <window.Canvas doc={doc} selected={selected} onSelect={setSelected} zoom={zoom} />

        {panels.right && (
          <div className="glass-medium" style={{ width: "var(--dock-right-width)", flex: "none",
            borderLeft: "1px solid var(--hairline)", overflow: "auto", borderRadius: 0 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, height: "var(--panel-header-height)",
              padding: "0 12px", borderBottom: "1px solid var(--hairline)", position: "sticky", top: 0,
              background: "var(--glass-tint-medium)", backdropFilter: "blur(30px)",
              WebkitBackdropFilter: "blur(30px)", zIndex: 2 }}>
              <i className="ph-fill ph-sliders-horizontal" style={{ fontSize: 15, color: "var(--text-accent)" }} />
              <span className="exp-panel-title" style={{ color: "var(--text-accent)", flex: 1 }}>Properties</span>
              <i className="ph ph-caret-down" style={{ fontSize: 13, color: "var(--text-tertiary)" }} />
            </div>
            <window.Inspector doc={doc} selected={selected} update={update} />
          </div>
        )}
      </div>
    </div>
  );
}

window.EditorShell = EditorShell;
