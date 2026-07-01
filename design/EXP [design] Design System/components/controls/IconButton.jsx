import React from "react";
import { Icon } from "./Icon.jsx";

/**
 * IconButton — square, borderless glyph button for toolbars, inspector rows, and
 * the tools strip. Active state uses the accent-tinted fill (accent @ 0.22, the
 * app's tool-button highlight); hover is a soft neutral wash.
 */
export function IconButton({
  icon,
  weight,                    // overrides; defaults derived from active
  active = false,
  size = "md",               // sm | md | lg
  disabled = false,
  title,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const dim = { sm: 22, md: 28, lg: 30 }[size];
  const glyph = { sm: 13, md: 15, lg: 16 }[size];

  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      aria-pressed={active}
      disabled={disabled}
      onClick={disabled ? undefined : onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        width: dim, height: dim, display: "inline-flex", alignItems: "center",
        justifyContent: "center", borderRadius: "var(--radius-tool)",
        border: "none", cursor: disabled ? "default" : "pointer",
        background: active ? "var(--accent-subtle-2)" : hover ? "var(--row-hover)" : "transparent",
        color: active ? "var(--text-accent)" : disabled ? "var(--text-quaternary)" : "var(--text-primary)",
        transition: "background var(--dur-fast) var(--ease-standard), color var(--dur-fast)",
        outline: "none", ...style,
      }}
      {...rest}
    >
      <Icon name={icon} weight={weight || (active ? "fill" : "regular")} size={glyph} />
    </button>
  );
}
