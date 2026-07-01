import React from "react";
import { Icon } from "./Icon.jsx";

/**
 * Button — EXP's primary action control. Default variant is Liquid Glass with an
 * accent tint; secondary is a neutral glass; ghost is borderless. Matches the
 * VISUAL-HANDOFF "Primary button" spec (radius 8, lit edge, sheen, AA focus).
 */
export function Button({
  children,
  variant = "primary",      // primary | secondary | ghost | destructive
  size = "md",              // sm | md | lg
  icon,                     // optional Phosphor icon name (leading)
  iconWeight = "bold",
  disabled = false,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [press, setPress] = React.useState(false);

  const sizes = {
    sm: { h: 22, px: 10, fs: 12, gap: 5 },
    md: { h: 30, px: 14, fs: 13, gap: 6 },
    lg: { h: 36, px: 18, fs: 14, gap: 7 },
  }[size];

  const base = {
    display: "inline-flex", alignItems: "center", justifyContent: "center",
    gap: sizes.gap, height: sizes.h, padding: `0 ${sizes.px}px`,
    borderRadius: "var(--radius-button)", fontFamily: "var(--font-sans)",
    fontSize: sizes.fs, fontWeight: "var(--w-medium)", letterSpacing: "-0.01em",
    cursor: disabled ? "default" : "pointer", border: "1px solid transparent",
    whiteSpace: "nowrap", userSelect: "none", outline: "none",
    transition: "background var(--dur-fast) var(--ease-standard), transform var(--dur-fast) var(--ease-standard), box-shadow var(--dur-fast)",
    transform: press && !disabled ? "translateY(0.5px) scale(0.985)" : "none",
    opacity: disabled ? 0.4 : 1,
  };

  const variants = {
    primary: {
      background: press ? "var(--accent-press)" : hover ? "var(--accent-hover)" : "var(--accent)",
      color: "var(--text-on-accent)",
      borderColor: "rgba(255,255,255,0.18)",
      boxShadow: press ? "var(--shadow-1)" : "var(--shadow-2), inset 0 1px 0 rgba(255,255,255,0.25)",
    },
    secondary: {
      background: hover ? "var(--row-active)" : "var(--surface-field)",
      color: "var(--text-primary)",
      borderColor: "var(--border-glass)",
      boxShadow: "var(--glass-inner-hi)",
    },
    ghost: {
      background: hover ? "var(--row-hover)" : "transparent",
      color: "var(--text-primary)", borderColor: "transparent",
    },
    destructive: {
      background: press ? "#c8352c" : hover ? "#ff5a50" : "var(--red)",
      color: "#fff", borderColor: "rgba(255,255,255,0.18)",
      boxShadow: "var(--shadow-1)",
    },
  }[variant];

  const focusRing = { boxShadow: `${variants.boxShadow || ""}, var(--glow-accent)` };

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={disabled ? undefined : onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => { setHover(false); setPress(false); }}
      onMouseDown={() => setPress(true)}
      onMouseUp={() => setPress(false)}
      onFocus={(e) => { if (!disabled) Object.assign(e.currentTarget.style, focusRing); }}
      onBlur={(e) => { e.currentTarget.style.boxShadow = variants.boxShadow || "none"; }}
      style={{ ...base, ...variants, ...style }}
      {...rest}
    >
      {icon && <Icon name={icon} weight={iconWeight} size={sizes.fs + 1} />}
      {children}
    </button>
  );
}
