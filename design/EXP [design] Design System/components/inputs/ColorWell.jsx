import React from "react";

/**
 * ColorWell — the Fill / Stroke swatch in the inspector. Shows the colour over a
 * checkerboard (so alpha reads), with an optional trailing label. Click is wired
 * via onClick (host opens its own colour popover). Covers both the app's ColorWell
 * (stroke) and PaintWell (fill) — pass a CSS gradient string for a gradient fill.
 */
export function ColorWell({ color = "#ffffff", label, onClick, size = "md", style = {} }) {
  const dims = { sm: { w: 40, h: 18 }, md: { w: 52, h: 22 } }[size];
  const swatch = (
    <button type="button" onClick={onClick}
      style={{
        width: dims.w, height: dims.h, padding: 0, borderRadius: 5, cursor: "pointer",
        border: "1px solid var(--border-strong)", overflow: "hidden", position: "relative",
        // checkerboard under transparent colours
        backgroundImage: "linear-gradient(45deg,#999 25%,transparent 25%),linear-gradient(-45deg,#999 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#999 75%),linear-gradient(-45deg,transparent 75%,#999 75%)",
        backgroundSize: "8px 8px", backgroundPosition: "0 0,0 4px,4px -4px,-4px 0px",
        boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
      }}>
      <span style={{ position: "absolute", inset: 0, background: color }} />
    </button>
  );
  if (!label) return <span style={style}>{swatch}</span>;
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, ...style }}>
      <span style={{ fontFamily: "var(--font-sans)", fontSize: 12, fontWeight: "var(--w-light)", color: "var(--text-secondary)" }}>{label}</span>
      {swatch}
    </div>
  );
}
