import React from "react";

/**
 * Switch — macOS-style toggle. The app uses `.controlSize(.mini)` switches in the
 * inspector (Auto Layout / Auto Padding), so `mini` is the default size here.
 */
export function Switch({ checked = false, onChange, disabled = false, size = "mini", style = {} }) {
  const dims = { mini: { w: 26, h: 15, k: 11 }, small: { w: 32, h: 19, k: 15 } }[size];
  const pad = (dims.h - dims.k) / 2;
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => !disabled && onChange && onChange(!checked)}
      style={{
        width: dims.w, height: dims.h, borderRadius: 999, border: "none",
        padding: 0, cursor: disabled ? "default" : "pointer", position: "relative",
        background: checked ? "var(--accent)" : "var(--n-400)",
        boxShadow: checked ? "inset 0 1px 2px rgba(0,0,0,0.2)" : "inset 0 1px 2px rgba(0,0,0,0.3)",
        opacity: disabled ? 0.4 : 1,
        transition: "background var(--dur-base) var(--ease-standard)", outline: "none",
      }}
    >
      <span
        style={{
          position: "absolute", top: pad, left: checked ? dims.w - dims.k - pad : pad,
          width: dims.k, height: dims.k, borderRadius: 999, background: "#fff",
          boxShadow: "0 1px 2px rgba(0,0,0,0.35)",
          transition: "left var(--dur-base) var(--ease-emphasis)",
        }}
      />
    </button>
  );
}
