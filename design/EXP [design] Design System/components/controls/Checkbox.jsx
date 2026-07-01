import React from "react";

/**
 * Checkbox — the inspector's square check (Show grid, Snap to grid). Filled with
 * the accent when on; a hairline square when off.
 */
export function Checkbox({ checked = false, onChange, label, disabled = false, style = {} }) {
  const box = (
    <span
      style={{
        width: 15, height: 15, borderRadius: 4, flex: "none",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
        background: checked ? "var(--accent)" : "var(--surface-field)",
        border: `1px solid ${checked ? "var(--accent)" : "var(--border-strong)"}`,
        boxShadow: checked ? "none" : "inset 0 1px 1px rgba(0,0,0,0.2)",
        transition: "background var(--dur-fast), border-color var(--dur-fast)",
      }}
    >
      {checked && <i className="ph-bold ph-check" style={{ fontSize: 11, color: "#fff" }} />}
    </span>
  );
  if (!label) {
    return (
      <button type="button" role="checkbox" aria-checked={checked} disabled={disabled}
        onClick={() => !disabled && onChange && onChange(!checked)}
        style={{ background: "none", border: "none", padding: 0, cursor: disabled ? "default" : "pointer", opacity: disabled ? 0.4 : 1, ...style }}>
        {box}
      </button>
    );
  }
  return (
    <label style={{ display: "inline-flex", alignItems: "center", gap: 8, cursor: disabled ? "default" : "pointer", opacity: disabled ? 0.4 : 1, ...style }}>
      <button type="button" role="checkbox" aria-checked={checked} disabled={disabled}
        onClick={() => !disabled && onChange && onChange(!checked)}
        style={{ background: "none", border: "none", padding: 0, cursor: "inherit" }}>
        {box}
      </button>
      <span style={{ fontFamily: "var(--font-sans)", fontSize: 12, fontWeight: "var(--w-light)", color: "var(--text-secondary)" }}>{label}</span>
    </label>
  );
}
