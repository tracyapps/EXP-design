// Inspector — the right Properties panel. Renders the right body per selection:
// a shape (full controls), an artboard (name/size/bg/layout grids), or nothing.
// Composes the DS field primitives.
const NS = window.EXPDesignDesignSystem_fb82b2;

function Row({ children, style }) {
  return <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "0 var(--panel-pad-h)", ...style }}>{children}</div>;
}

function AlignGrid() {
  const { SegmentedControl, IconButton } = NS;
  const [to, setTo] = React.useState("selection");
  const aligns = ["align-left", "align-center-horizontal", "align-right",
                  "align-top", "align-center-vertical", "align-bottom"];
  return (
    <div style={{ padding: "10px var(--panel-pad-h)" }}>
      <div className="exp-section-title" style={{ marginBottom: 8 }}>Align</div>
      <Row style={{ padding: 0, marginBottom: 10, gap: 10 }}>
        <span style={{ fontSize: 12, color: "var(--text-tertiary)" }}>To</span>
        <SegmentedControl options={[{ value: "selection", label: "Selection" }, { value: "artboard", label: "Artboard" }]}
          value={to} onChange={setTo} />
      </Row>
      <div style={{ display: "flex", gap: 14 }}>
        <div style={{ display: "flex", gap: 2 }}>
          {aligns.slice(0, 3).map((a) => <AlignBtn key={a} icon={a} />)}
        </div>
        <div style={{ display: "flex", gap: 2 }}>
          {aligns.slice(3).map((a) => <AlignBtn key={a} icon={a} />)}
        </div>
      </div>
      <Row style={{ padding: 0, marginTop: 12, gap: 14 }}>
        <span style={{ fontSize: 12, color: "var(--text-tertiary)" }}>Distribute</span>
        <div style={{ display: "flex", gap: 6 }}>
          <AlignBtn icon="rows" /><AlignBtn icon="columns" />
        </div>
      </Row>
    </div>
  );
}
function AlignBtn({ icon }) {
  const [h, setH] = React.useState(false);
  return (
    <button onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 38, height: 32, borderRadius: 6, border: "1px solid var(--border-soft)",
        background: h ? "var(--row-hover)" : "var(--surface-card)", cursor: "pointer",
        color: "var(--text-secondary)", display: "inline-flex", alignItems: "center", justifyContent: "center" }}>
      <i className={`ph ph-${icon}`} style={{ fontSize: 15 }} />
    </button>
  );
}

function ShapeInspector({ layer, doc, update }) {
  const { TextField, NumericField, Select, ColorWell, Divider, SectionHeader } = NS;
  return (
    <div>
      <div style={{ padding: "12px var(--panel-pad-h) 8px" }}>
        <div className="exp-section-title" style={{ marginBottom: 6 }}>Layer</div>
        <TextField value={layer.name} weight="medium" onChange={(v) => update({ name: v })} />
      </div>
      <Row style={{ marginBottom: 8 }}>
        <NumericField label="X" value={layer.X} onChange={(v) => update({ X: v })} />
        <NumericField label="Y" value={layer.Y} onChange={(v) => update({ Y: v })} />
      </Row>
      <Row style={{ marginBottom: 8 }}>
        <NumericField label="W" value={layer.W} onChange={(v) => update({ W: v })} />
        <NumericField label="H" value={layer.H} onChange={(v) => update({ H: v })} />
      </Row>
      <Row style={{ marginBottom: 8, justifyContent: "space-between" }}>
        <NumericField label="R" value={layer.rot} unit="°" width={64} onChange={(v) => update({ rot: v })} />
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <span style={{ fontSize: 12, color: "var(--text-tertiary)" }}>Opacity</span>
          <NumericField label="" value={layer.opacity} unit="%" min={0} max={100} width={52} onChange={(v) => update({ opacity: v })} />
        </div>
      </Row>
      <Row style={{ marginBottom: 10, gap: 8 }}>
        <span style={{ fontSize: 12, color: "var(--text-tertiary)" }}>Blend</span>
        <Select options={doc.blendModes} value={layer.blend} onChange={(v) => update({ blend: v })} width={150} />
      </Row>
      <Divider />
      <Row style={{ padding: "12px var(--panel-pad-h)" }}>
        <ColorWell label="Fill" color={layer.fill} style={{ flex: 1 }} />
      </Row>
      <Divider />
      <div style={{ padding: "10px var(--panel-pad-h) 4px" }}>
        <div className="exp-section-title" style={{ marginBottom: 8 }}>Stroke</div>
        <Row style={{ padding: 0, marginBottom: 8 }}>
          <ColorWell label="Color" color={layer.stroke} style={{ flex: 1 }} />
        </Row>
        <Row style={{ padding: 0 }}>
          <span style={{ fontSize: 12, color: "var(--text-tertiary)", flex: 1 }}>Width</span>
          <NumericField label="" value={layer.strokeW} width={56} onChange={(v) => update({ strokeW: v })} />
        </Row>
      </div>
      <Divider />
      <AlignGrid />
      <Divider />
      <SectionHeader title="Effects" action="plus" />
      <div style={{ padding: "0 var(--panel-pad-h) 14px", fontSize: 12, color: "var(--text-tertiary)" }}>No effects</div>
    </div>
  );
}

function ArtboardInspector({ ab }) {
  const { TextField, NumericField, ColorWell, Divider, SectionHeader } = NS;
  return (
    <div>
      <div style={{ padding: "12px var(--panel-pad-h) 8px" }}>
        <div className="exp-section-title" style={{ marginBottom: 6 }}>Artboard</div>
        <TextField value={ab.name} weight="medium" onChange={() => {}} />
      </div>
      <Row style={{ marginBottom: 8 }}>
        <NumericField label="X" value={ab.x} onChange={() => {}} />
        <NumericField label="Y" value={ab.y} onChange={() => {}} />
      </Row>
      <Row style={{ marginBottom: 10 }}>
        <NumericField label="W" value={ab.w} onChange={() => {}} />
        <NumericField label="H" value={ab.h} onChange={() => {}} />
      </Row>
      <Divider />
      <Row style={{ padding: "12px var(--panel-pad-h)" }}>
        <ColorWell label="Background" color={ab.bg} style={{ flex: 1 }} />
      </Row>
      <Divider />
      <SectionHeader title="Layout Grids" action="plus" />
      <div style={{ padding: "0 var(--panel-pad-h) 14px", fontSize: 12, color: "var(--text-tertiary)" }}>No layout grids</div>
    </div>
  );
}

function Inspector({ doc, selected, update }) {
  const layer = doc.layers.find((l) => l.id === selected && l.X != null);
  return (
    <div>
      {layer ? <ShapeInspector layer={layer} doc={doc} update={update} />
        : (selected === "ab" || selected == null)
          ? <ArtboardInspector ab={doc.artboards[0]} />
          : <div style={{ padding: "16px var(--panel-pad-h)", fontSize: 12, color: "var(--text-tertiary)" }}>No selection</div>}
    </div>
  );
}

window.Inspector = Inspector;
