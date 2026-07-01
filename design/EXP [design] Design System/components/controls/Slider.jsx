import React from "react";

/**
 * Slider — the inspector's zoom/value slider. Thin track, accent-filled left of
 * the knob, round draggable thumb. Controlled via value/min/max.
 */
export function Slider({ value, min = 0, max = 100, step = 1, onChange, style = {} }) {
  const ref = React.useRef(null);
  const pct = Math.max(0, Math.min(1, (value - min) / (max - min)));

  const setFromClientX = (clientX) => {
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    const t = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
    const raw = min + t * (max - min);
    const snapped = Math.round(raw / step) * step;
    onChange && onChange(Math.max(min, Math.min(max, snapped)));
  };
  const onDown = (e) => {
    setFromClientX(e.clientX);
    const move = (ev) => setFromClientX(ev.clientX);
    const up = () => { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); };
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  };

  return (
    <div ref={ref} onMouseDown={onDown}
      style={{ position: "relative", height: 18, display: "flex", alignItems: "center", cursor: "pointer", flex: 1, ...style }}>
      <div style={{ position: "absolute", left: 0, right: 0, height: 3, borderRadius: 999, background: "var(--n-400)" }} />
      <div style={{ position: "absolute", left: 0, width: `${pct * 100}%`, height: 3, borderRadius: 999, background: "var(--accent)" }} />
      <div style={{
        position: "absolute", left: `calc(${pct * 100}% - 7px)`, width: 14, height: 14,
        borderRadius: 999, background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(0,0,0,0.3)",
      }} />
    </div>
  );
}
