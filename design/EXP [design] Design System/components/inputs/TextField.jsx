import React from "react";

/**
 * TextField — rounded-border text input. Used for the layer/artboard name and any
 * single-line string. Focus shows the accent ring.
 */
export function TextField({
  value, onChange, placeholder, weight = "light", align = "left",
  disabled = false, monospace = false, style = {}, ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  return (
    <input
      type="text"
      value={value}
      placeholder={placeholder}
      disabled={disabled}
      onChange={(e) => onChange && onChange(e.target.value)}
      onFocus={() => setFocus(true)}
      onBlur={() => setFocus(false)}
      style={{
        width: "100%", boxSizing: "border-box", height: "var(--control-h)",
        padding: "0 8px", borderRadius: "var(--radius-field)",
        background: focus ? "var(--surface-field-focus)" : "var(--surface-field)",
        border: `1px solid ${focus ? "var(--accent)" : "var(--border-strong)"}`,
        boxShadow: focus ? "0 0 0 3px var(--accent-subtle)" : "inset 0 1px 1px rgba(0,0,0,0.18)",
        color: "var(--text-primary)", textAlign: align,
        fontFamily: monospace ? "var(--font-mono)" : "var(--font-sans)",
        fontSize: 12, fontWeight: `var(--w-${weight})`,
        outline: "none", transition: "border-color var(--dur-fast), box-shadow var(--dur-fast), background var(--dur-fast)",
        opacity: disabled ? 0.5 : 1, ...style,
      }}
      {...rest}
    />
  );
}
