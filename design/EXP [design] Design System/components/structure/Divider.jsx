import React from "react";

/** Divider — a hairline separator (separatorColor analog). Horizontal by default. */
export function Divider({ vertical = false, inset = 0, style = {} }) {
  return vertical ? (
    <span style={{ width: 1, alignSelf: "stretch", background: "var(--hairline)", margin: `${inset}px 0`, flex: "none", ...style }} />
  ) : (
    <div style={{ height: 1, background: "var(--hairline)", margin: `0 ${inset}px`, ...style }} />
  );
}
