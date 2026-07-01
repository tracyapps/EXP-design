import React from "react";

/**
 * SectionHeader — an inspector section label ("Effects", "Layout Grids", "Stroke")
 * in ultralight secondary type, with an optional trailing action (a + or chevron).
 */
export function SectionHeader({ title, action, onAction, style = {} }) {
  return (
    <div style={{
      display: "flex", alignItems: "center", justifyContent: "space-between",
      padding: "10px var(--panel-pad-h) 4px", ...style,
    }}>
      <span style={{
        fontFamily: "var(--font-display)", fontSize: "var(--t-mini)", fontWeight: "var(--w-ultralight)",
        textTransform: "uppercase", letterSpacing: "var(--tr-wide)", color: "var(--text-secondary)",
      }}>{title}</span>
      {action && (
        <button type="button" onClick={onAction} aria-label={`${title} action`}
          style={{ background: "none", border: "none", padding: 2, cursor: "pointer",
            color: "var(--text-tertiary)", display: "inline-flex" }}>
          <i className={`ph ph-${action}`} style={{ fontSize: 14 }} />
        </button>
      )}
    </div>
  );
}
