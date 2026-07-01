import React from "react";

/**
 * Tooltip — the macOS help bubble shown on hover. A glass-thin popover with the
 * label and an optional keyboard hint (e.g. "Select  V"). Wrap any trigger.
 */
export function Tooltip({ label, shortcut, side = "top", children, style = {} }) {
  const [show, setShow] = React.useState(false);
  const pos = {
    top: { bottom: "calc(100% + 6px)", left: "50%", transform: "translateX(-50%)" },
    bottom: { top: "calc(100% + 6px)", left: "50%", transform: "translateX(-50%)" },
    right: { left: "calc(100% + 6px)", top: "50%", transform: "translateY(-50%)" },
    left: { right: "calc(100% + 6px)", top: "50%", transform: "translateY(-50%)" },
  }[side];
  return (
    <span style={{ position: "relative", display: "inline-flex", ...style }}
      onMouseEnter={() => setShow(true)} onMouseLeave={() => setShow(false)}>
      {children}
      {show && (
        <span className="glass-thin glass-edge" style={{
          position: "absolute", ...pos, zIndex: 100, display: "inline-flex", alignItems: "center", gap: 7,
          padding: "4px 8px", borderRadius: 6, boxShadow: "var(--shadow-popover)",
          fontFamily: "var(--font-sans)", fontSize: 11, fontWeight: "var(--w-light)",
          color: "var(--text-primary)", whiteSpace: "nowrap", pointerEvents: "none",
        }}>
          {label}
          {shortcut && <kbd style={{ fontFamily: "var(--font-mono)", fontSize: 10,
            color: "var(--text-tertiary)", background: "var(--surface-field)",
            padding: "1px 4px", borderRadius: 3, border: "1px solid var(--border-soft)" }}>{shortcut}</kbd>}
        </span>
      )}
    </span>
  );
}
