import React from "react";

/**
 * NumericField — the inspector's X/Y/W/H/opacity field: an optional single-letter
 * label, a right-aligned monospaced-digit value, and a trailing unit. Drag-on-
 * label scrubbing is omitted (cosmetic kit) but click-to-edit works.
 */
export function NumericField({
  label, value, onChange, unit, min, max, width = 56, disabled = false, style = {},
}) {
  const [focus, setFocus] = React.useState(false);
  const commit = (raw) => {
    let n = parseFloat(raw);
    if (Number.isNaN(n)) return;
    if (min != null) n = Math.max(min, n);
    if (max != null) n = Math.min(max, n);
    onChange && onChange(n);
  };
  return (
    <div style={{ display: "inline-flex", alignItems: "center", gap: 4, ...style }}>
      {label && (
        <span style={{ fontFamily: "var(--font-sans)", fontSize: 12, fontWeight: "var(--w-light)",
          color: "var(--text-tertiary)", width: 12, textAlign: "left", flex: "none" }}>{label}</span>
      )}
      <div style={{ position: "relative", width, flex: "none" }}>
        <input
          type="text"
          defaultValue={value}
          key={value}
          disabled={disabled}
          onFocus={() => setFocus(true)}
          onBlur={(e) => { setFocus(false); commit(e.target.value); }}
          onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
          style={{
            width: "100%", boxSizing: "border-box", height: "var(--control-h)",
            padding: unit ? "0 18px 0 8px" : "0 8px", borderRadius: "var(--radius-field)",
            background: focus ? "var(--surface-field-focus)" : "var(--surface-field)",
            border: `1px solid ${focus ? "var(--accent)" : "var(--border-strong)"}`,
            boxShadow: focus ? "0 0 0 3px var(--accent-subtle)" : "inset 0 1px 1px rgba(0,0,0,0.18)",
            color: "var(--text-primary)", textAlign: "right",
            fontFamily: "var(--font-sans)", fontSize: 12, fontVariantNumeric: "tabular-nums",
            outline: "none", opacity: disabled ? 0.5 : 1,
            transition: "border-color var(--dur-fast), box-shadow var(--dur-fast)",
          }}
        />
        {unit && (
          <span style={{ position: "absolute", right: 7, top: "50%", transform: "translateY(-50%)",
            fontFamily: "var(--font-sans)", fontSize: 11, color: "var(--text-tertiary)", pointerEvents: "none" }}>{unit}</span>
        )}
      </div>
    </div>
  );
}
