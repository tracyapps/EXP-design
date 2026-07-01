import React from "react";

/**
 * Icon — thin wrapper over Phosphor Icons (web font), the closest CDN stand-in
 * for the app's native SF Symbols. The host page must load the Phosphor web font
 * (see any card/kit <head>). `weight` maps to Phosphor weights; the app's default
 * "hierarchical, solid" feel maps best to "fill" for active glyphs and "regular"
 * for idle ones.
 */
export function Icon({ name, weight = "regular", size = 16, color = "currentColor", style = {}, ...rest }) {
  const cls = weight === "regular" ? `ph ph-${name}` : `ph-${weight} ph-${name}`;
  return (
    <i
      className={cls}
      style={{ fontSize: size, color, lineHeight: 1, display: "inline-flex", ...style }}
      {...rest}
    />
  );
}
