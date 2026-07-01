import React from "react";

/**
 * Select — the inspector's dropdown (Blend mode, line-height unit). A glass-field
 * trigger with a chevron; opens a glass popover list. Controlled by value.
 */
export function Select({ options, value, onChange, width, disabled = false, style = {} }) {
  const opts = options.map((o) => (typeof o === "string" ? { value: o, label: o } : o));
  const [open, setOpen] = React.useState(false);
  const [hover, setHover] = React.useState(false);
  const ref = React.useRef(null);
  const current = opts.find((o) => o.value === value) || opts[0];

  React.useEffect(() => {
    if (!open) return;
    const close = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    window.addEventListener("mousedown", close);
    return () => window.removeEventListener("mousedown", close);
  }, [open]);

  return (
    <div ref={ref} style={{ position: "relative", width: width || "auto", ...style }}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((o) => !o)}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          width: "100%", boxSizing: "border-box", height: "var(--control-h)",
          display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8,
          padding: "0 6px 0 8px", borderRadius: "var(--radius-field)",
          background: hover ? "var(--surface-field-focus)" : "var(--surface-field)",
          border: "1px solid var(--border-strong)", cursor: disabled ? "default" : "pointer",
          color: "var(--text-primary)", fontFamily: "var(--font-sans)", fontSize: 12,
          fontWeight: "var(--w-light)", outline: "none", opacity: disabled ? 0.5 : 1,
        }}
      >
        <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{current?.label}</span>
        <i className="ph-bold ph-caret-up-down" style={{ fontSize: 11, color: "var(--text-tertiary)" }} />
      </button>
      {open && (
        <div className="glass-medium glass-edge" style={{
          position: "absolute", top: "calc(100% + 4px)", left: 0, minWidth: "100%", zIndex: 50,
          padding: 4, borderRadius: "var(--radius-row)", boxShadow: "var(--shadow-popover)",
        }}>
          {opts.map((o) => {
            const sel = o.value === value;
            return (
              <button key={o.value} type="button"
                onClick={() => { onChange && onChange(o.value); setOpen(false); }}
                style={{
                  width: "100%", display: "flex", alignItems: "center", gap: 8, height: 24,
                  padding: "0 8px", border: "none", cursor: "pointer", textAlign: "left",
                  borderRadius: 4, background: sel ? "var(--accent)" : "transparent",
                  color: sel ? "#fff" : "var(--text-primary)", fontFamily: "var(--font-sans)",
                  fontSize: 12, fontWeight: "var(--w-light)", whiteSpace: "nowrap",
                }}
                onMouseEnter={(e) => { if (!sel) e.currentTarget.style.background = "var(--row-hover)"; }}
                onMouseLeave={(e) => { if (!sel) e.currentTarget.style.background = "transparent"; }}
              >
                <span style={{ width: 12, flex: "none" }}>{sel && <i className="ph-bold ph-check" style={{ fontSize: 11 }} />}</span>
                {o.label}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
