import React from "react";

/**
 * LayerRow — one row in the Layers panel. Anatomy: indent · disclosure chevron ·
 * eye (visibility) · type glyph · name (SF Compact) · lock. Selected rows take the
 * accent-subtle fill with an accent left edge; locked rows dim. Matches the app's
 * layer tree exactly (icons map to node kinds).
 */
const KIND_ICON = {
  text: "text-aa", image: "image", component: "squares-four", instance: "squares-four",
  group: "folder-simple", rectangle: "square", ellipse: "circle", line: "line-segment",
  path: "scribble-loop", polygon: "triangle", artboard: "frame-corners",
};

export function LayerRow({
  name, kind = "rectangle", depth = 0, selected = false, hidden = false, locked = false,
  expandable = false, expanded = false, onToggle, onSelect, onToggleHidden, onToggleLock, style = {},
}) {
  const [hover, setHover] = React.useState(false);
  const icon = KIND_ICON[kind] || "square";
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={onSelect}
      style={{
        display: "flex", alignItems: "center", gap: 6, height: 28, paddingRight: 8,
        paddingLeft: 6 + depth * 15, cursor: "default", position: "relative",
        background: selected ? "var(--accent-subtle)" : hover ? "var(--row-hover)" : "transparent",
        boxShadow: selected ? "inset 2px 0 0 var(--accent)" : "none",
        opacity: hidden ? 0.45 : 1, ...style,
      }}
    >
      <button type="button" onClick={(e) => { e.stopPropagation(); onToggle && onToggle(); }}
        style={{ width: 12, flex: "none", background: "none", border: "none", padding: 0,
          cursor: "pointer", color: "var(--text-tertiary)", visibility: expandable ? "visible" : "hidden" }}>
        <i className="ph-bold ph-caret-right" style={{ fontSize: 10, display: "inline-block",
          transform: expanded ? "rotate(90deg)" : "none", transition: "transform var(--dur-fast)" }} />
      </button>

      <button type="button" onClick={(e) => { e.stopPropagation(); onToggleHidden && onToggleHidden(); }}
        title={hidden ? "Show" : "Hide"} style={{ width: 16, flex: "none", background: "none", border: "none",
          padding: 0, cursor: "pointer", color: hover || hidden ? "var(--text-secondary)" : "var(--text-tertiary)" }}>
        <i className={hidden ? "ph ph-eye-slash" : "ph ph-eye"} style={{ fontSize: 13 }} />
      </button>

      <i className={`ph ph-${icon}`} style={{ fontSize: 13, flex: "none",
        color: selected ? "var(--text-accent)" : "var(--text-tertiary)" }} />

      <span style={{ flex: 1, fontFamily: "var(--font-condensed)", fontSize: 12,
        fontWeight: selected ? "var(--w-regular)" : "var(--w-light)",
        color: selected ? "var(--text-primary)" : "var(--text-primary)",
        whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{name}</span>

      <button type="button" onClick={(e) => { e.stopPropagation(); onToggleLock && onToggleLock(); }}
        title={locked ? "Unlock" : "Lock"} style={{ width: 16, flex: "none", background: "none", border: "none",
          padding: 0, cursor: "pointer", opacity: locked || hover ? 1 : 0,
          color: locked ? "var(--text-secondary)" : "var(--text-tertiary)", transition: "opacity var(--dur-fast)" }}>
        <i className={locked ? "ph-fill ph-lock-simple" : "ph ph-lock-simple-open"} style={{ fontSize: 13 }} />
      </button>
    </div>
  );
}
