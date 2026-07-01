import React from "react";

/**
 * Badge — a small status/count pill. `dot` adds a leading status dot (the lime
 * "online", or any semantic colour). Used for component counts ("8 layers"),
 * status, and the live brand-lime indicator.
 */
const TONES = {
  neutral: { bg: "var(--surface-card)", fg: "var(--text-secondary)", bd: "var(--border-soft)" },
  accent:  { bg: "var(--accent-subtle)", fg: "var(--text-accent)", bd: "transparent" },
  brand:   { bg: "rgba(76,230,46,0.14)", fg: "var(--text-brand)", bd: "transparent" },
  red:     { bg: "rgba(255,69,58,0.16)", fg: "#ff6a60", bd: "transparent" },
};

export function Badge({ children, tone = "neutral", dot = false, dotColor, style = {} }) {
  const t = TONES[tone] || TONES.neutral;
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 5, height: 18,
      padding: "0 7px", borderRadius: "var(--radius-pill)", background: t.bg,
      border: `1px solid ${t.bd}`, color: t.fg, fontFamily: "var(--font-sans)",
      fontSize: 10.5, fontWeight: "var(--w-medium)", lineHeight: 1,
      fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap", ...style,
    }}>
      {dot && <span style={{ width: 6, height: 6, borderRadius: 999,
        background: dotColor || (tone === "brand" ? "var(--brand-lime)" : "currentColor"),
        boxShadow: tone === "brand" ? "var(--glow-lime)" : "none" }} />}
      {children}
    </span>
  );
}
