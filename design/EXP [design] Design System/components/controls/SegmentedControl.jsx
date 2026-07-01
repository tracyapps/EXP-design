import React from "react";

/**
 * SegmentedControl — the app's pill toggle (e.g. "Selection / Artboard", row vs
 * column, Gap vs Space Between). Selected segment shows the accent fill; the
 * track is an inset glass groove.
 */
export function SegmentedControl({
  options,                  // [{ value, label?, icon? }] or ["a","b"]
  value,
  onChange,
  size = "md",              // sm | md
  fill = "accent",          // accent | neutral
  style = {},
}) {
  const opts = options.map((o) => (typeof o === "string" ? { value: o, label: o } : o));
  const h = size === "sm" ? 22 : 28;
  const fs = size === "sm" ? 11 : 12.5;

  return (
    <div
      role="tablist"
      style={{
        display: "inline-flex", height: h, padding: 2, gap: 2,
        background: "var(--surface-field)", borderRadius: "var(--radius-control)",
        border: "1px solid var(--border-soft)", boxShadow: "inset 0 1px 2px rgba(0,0,0,0.25)",
        ...style,
      }}
    >
      {opts.map((o) => {
        const sel = o.value === value;
        const selBg = fill === "accent" ? "var(--accent)" : "var(--n-400)";
        return (
          <button
            key={o.value}
            role="tab"
            aria-selected={sel}
            onClick={() => onChange && onChange(o.value)}
            style={{
              display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 5,
              height: h - 4, padding: "0 12px", border: "none", cursor: "pointer",
              borderRadius: "calc(var(--radius-control) - 2px)",
              fontFamily: "var(--font-sans)", fontSize: fs,
              fontWeight: sel ? "var(--w-medium)" : "var(--w-light)",
              background: sel ? selBg : "transparent",
              color: sel ? (fill === "accent" ? "var(--text-on-accent)" : "var(--text-primary)") : "var(--text-secondary)",
              boxShadow: sel ? "var(--shadow-1), inset 0 1px 0 rgba(255,255,255,0.2)" : "none",
              transition: "background var(--dur-fast) var(--ease-standard), color var(--dur-fast)",
              whiteSpace: "nowrap",
            }}
          >
            {o.icon && <i className={`ph-bold ph-${o.icon}`} style={{ fontSize: fs + 1 }} />}
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
