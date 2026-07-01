// Canvas — the undesigned center surface: top + corner rulers, the dark "wall",
// and the white artboard with its label + selection chrome. Layers render as
// simple cosmetic blocks; the selected one shows handles. Per the brief the
// canvas itself stays minimal and token-isolated (--canvas-*).
const NS = window.EXPDesignDesignSystem_fb82b2;

function Ruler({ horizontal }) {
  const ticks = [];
  for (let i = 0; i < 28; i++) {
    const major = i % 5 === 0;
    ticks.push(
      <div key={i} style={{
        position: "absolute",
        ...(horizontal
          ? { left: `${i * 60}px`, top: major ? 8 : 13, width: 1, height: major ? 12 : 7 }
          : { top: `${i * 60}px`, left: major ? 8 : 13, height: 1, width: major ? 12 : 7 }),
        background: "var(--canvas-ruler-tick)",
      }}>
        {major && (
          <span style={{
            position: "absolute", fontSize: 9, fontFamily: "var(--font-mono)",
            color: "var(--canvas-ruler-tick)", whiteSpace: "nowrap",
            ...(horizontal ? { left: 3, top: -9 } : { top: 2, left: -2, writingMode: "vertical-rl" }),
          }}>{i * 100 - 300}</span>
        )}
      </div>
    );
  }
  return (
    <div style={{
      position: "absolute", background: "var(--canvas-ruler-bg)",
      backdropFilter: "blur(8px)", WebkitBackdropFilter: "blur(8px)",
      ...(horizontal
        ? { top: 0, left: "var(--ruler-size)", right: 0, height: "var(--ruler-size)", borderBottom: "1px solid var(--hairline)" }
        : { top: "var(--ruler-size)", left: 0, bottom: 0, width: "var(--ruler-size)", borderRight: "1px solid var(--hairline)" }),
      zIndex: 2,
    }}>{ticks}</div>
  );
}

function LayerBlock({ layer, selected, scale, onSelect }) {
  if (layer.X == null) return null;
  const isText = layer.kind === "text";
  const isEllipse = layer.kind === "ellipse";
  return (
    <div onClick={(e) => { e.stopPropagation(); onSelect(layer.id); }}
      style={{
        position: "absolute", left: layer.X * scale, top: layer.Y * scale,
        width: layer.W * scale, height: layer.H * scale,
        transform: `rotate(${layer.rot || 0}deg)`, opacity: (layer.opacity ?? 100) / 100,
        background: isText ? "transparent" : layer.fill,
        borderRadius: isEllipse ? "50%" : layer.kind === "component" ? 8 : 2,
        display: isText ? "flex" : "block", alignItems: "center",
        color: "#1a1a1c", fontSize: 15 * scale, fontWeight: "var(--w-light)",
        cursor: "pointer", outline: selected ? "1.5px solid var(--canvas-selection)" : "none",
        boxShadow: selected ? "0 0 0 1px rgba(10,132,255,0.3)" : "none",
        visibility: layer.hidden ? "hidden" : "visible",
      }}>
      {isText && <span>a text layer.</span>}
      {selected && ["nw", "ne", "sw", "se"].map((h) => (
        <span key={h} style={{
          position: "absolute", width: 7, height: 7, background: "#fff",
          border: "1px solid var(--canvas-selection)", borderRadius: 1,
          top: h[0] === "n" ? -4 : "auto", bottom: h[0] === "s" ? -4 : "auto",
          left: h[1] === "w" ? -4 : "auto", right: h[1] === "e" ? -4 : "auto",
        }} />
      ))}
    </div>
  );
}

function Canvas({ doc, selected, onSelect, zoom }) {
  const ab = doc.artboards[0];
  const scale = 0.62 * (zoom / 94);
  return (
    <div onClick={() => onSelect(null)} style={{
      position: "relative", flex: 1, overflow: "hidden", background: "var(--canvas-bg)",
      minWidth: 360,
    }}>
      <Ruler horizontal />
      <Ruler />
      {/* wall */}
      <div style={{ position: "absolute", inset: "var(--ruler-size) 0 0 var(--ruler-size)", overflow: "hidden" }}>
        <div style={{ position: "absolute", left: "50%", top: 70, transform: "translateX(-50%)" }}>
          {/* artboard label */}
          <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 8,
            color: selected === "ab" ? "var(--text-accent)" : "var(--text-secondary)" }}>
            <i className="ph ph-frame-corners" style={{ fontSize: 13 }} />
            <span style={{ fontSize: 12, fontWeight: "var(--w-medium)" }}>{ab.name}</span>
          </div>
          {/* artboard */}
          <div onClick={(e) => { e.stopPropagation(); onSelect("ab"); }}
            style={{
              position: "relative", width: ab.w * scale, height: ab.h * scale,
              background: "var(--canvas-artboard)", cursor: "pointer",
              outline: selected === "ab" ? "1.5px solid var(--canvas-selection)" : "none",
              boxShadow: "0 8px 40px rgba(0,0,0,0.4)",
            }}>
            {doc.layers.map((l) => (
              <LayerBlock key={l.id} layer={l} selected={selected === l.id} scale={scale} onSelect={onSelect} />
            ))}
          </div>
        </div>
      </div>
      {/* corner */}
      <div style={{ position: "absolute", top: 0, left: 0, width: "var(--ruler-size)", height: "var(--ruler-size)",
        background: "var(--canvas-ruler-bg)", borderRight: "1px solid var(--hairline)",
        borderBottom: "1px solid var(--hairline)", zIndex: 3 }} />
    </div>
  );
}

window.Canvas = Canvas;
