import React from "react";

/**
 * Panel — a Liquid Glass dock/floating panel shell. Wraps a PanelHeader-style bar
 * (icon + uppercase title + optional detach affordance) over a content area. The
 * default material is `medium` (the dock panel); pass `material="thin"` for an
 * inline tray.
 */
export function Panel({
  title, icon = "stack-simple", material = "medium", actions, detachable = true,
  accentTitle = false, children, style = {}, bodyStyle = {},
}) {
  return (
    <div className={`glass-${material} glass-edge`} style={{
      display: "flex", flexDirection: "column", borderRadius: "var(--radius-panel)",
      overflow: "hidden", minWidth: 220, ...style,
    }}>
      <div style={{
        display: "flex", alignItems: "center", gap: 8, height: "var(--panel-header-height)",
        padding: "0 10px", borderBottom: "1px solid var(--hairline)", flex: "none",
        position: "relative", zIndex: 1,
      }}>
        {icon && <i className={`ph-fill ph-${icon}`} style={{ fontSize: 15, color: accentTitle ? "var(--text-accent)" : "var(--text-secondary)" }} />}
        <span style={{
          fontFamily: "var(--font-sans)", fontSize: "var(--t-base)", fontWeight: "var(--w-regular)",
          textTransform: "uppercase", letterSpacing: "var(--tr-caps)",
          color: accentTitle ? "var(--text-accent)" : "var(--text-primary)", flex: 1,
        }}>{title}</span>
        {actions}
        {detachable && (
          <i className="ph ph-arrow-square-out" style={{ fontSize: 14, color: "var(--text-tertiary)", cursor: "pointer" }} title="Detach panel" />
        )}
      </div>
      <div style={{ flex: 1, overflow: "auto", position: "relative", zIndex: 1, ...bodyStyle }}>{children}</div>
    </div>
  );
}
