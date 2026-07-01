/* @ds-bundle: {"format":3,"namespace":"EXPDesignDesignSystem_fb82b2","components":[{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"Checkbox","sourcePath":"components/controls/Checkbox.jsx"},{"name":"Icon","sourcePath":"components/controls/Icon.jsx"},{"name":"IconButton","sourcePath":"components/controls/IconButton.jsx"},{"name":"SegmentedControl","sourcePath":"components/controls/SegmentedControl.jsx"},{"name":"Slider","sourcePath":"components/controls/Slider.jsx"},{"name":"Switch","sourcePath":"components/controls/Switch.jsx"},{"name":"Badge","sourcePath":"components/feedback/Badge.jsx"},{"name":"Tooltip","sourcePath":"components/feedback/Tooltip.jsx"},{"name":"ColorWell","sourcePath":"components/inputs/ColorWell.jsx"},{"name":"NumericField","sourcePath":"components/inputs/NumericField.jsx"},{"name":"Select","sourcePath":"components/inputs/Select.jsx"},{"name":"TextField","sourcePath":"components/inputs/TextField.jsx"},{"name":"Divider","sourcePath":"components/structure/Divider.jsx"},{"name":"LayerRow","sourcePath":"components/structure/LayerRow.jsx"},{"name":"Panel","sourcePath":"components/structure/Panel.jsx"},{"name":"SectionHeader","sourcePath":"components/structure/SectionHeader.jsx"},{"name":"ToolStrip","sourcePath":"components/structure/ToolStrip.jsx"}],"sourceHashes":{"components/controls/Button.jsx":"867e411d7e42","components/controls/Checkbox.jsx":"2444adb9a928","components/controls/Icon.jsx":"deefec8d5a30","components/controls/IconButton.jsx":"4c4113a1583b","components/controls/SegmentedControl.jsx":"f081613f3903","components/controls/Slider.jsx":"9f83016da5db","components/controls/Switch.jsx":"7a71dec50479","components/feedback/Badge.jsx":"bb890a9ec53f","components/feedback/Tooltip.jsx":"c6201dab5ce7","components/inputs/ColorWell.jsx":"c8769adb4b00","components/inputs/NumericField.jsx":"26df7c28a766","components/inputs/Select.jsx":"928645f3b26d","components/inputs/TextField.jsx":"0f195454a447","components/structure/Divider.jsx":"5570bf305fd4","components/structure/LayerRow.jsx":"fc047f24543e","components/structure/Panel.jsx":"fbec70369e9c","components/structure/SectionHeader.jsx":"38b8a4bb4f0e","components/structure/ToolStrip.jsx":"0a089bf79082","ui_kits/exp-editor/Canvas.jsx":"bb96cd1c099b","ui_kits/exp-editor/EditorShell.jsx":"7b028e9b2c84","ui_kits/exp-editor/Inspector.jsx":"04d4879ee13a","ui_kits/exp-editor/LayersPanel.jsx":"8ad7e4d1569a","ui_kits/exp-editor/TopBar.jsx":"b3a182c83255","ui_kits/exp-editor/data.js":"3b6372b7f73d"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.EXPDesignDesignSystem_fb82b2 = window.EXPDesignDesignSystem_fb82b2 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/controls/Checkbox.jsx
try { (() => {
/**
 * Checkbox — the inspector's square check (Show grid, Snap to grid). Filled with
 * the accent when on; a hairline square when off.
 */
function Checkbox({
  checked = false,
  onChange,
  label,
  disabled = false,
  style = {}
}) {
  const box = /*#__PURE__*/React.createElement("span", {
    style: {
      width: 15,
      height: 15,
      borderRadius: 4,
      flex: "none",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      background: checked ? "var(--accent)" : "var(--surface-field)",
      border: `1px solid ${checked ? "var(--accent)" : "var(--border-strong)"}`,
      boxShadow: checked ? "none" : "inset 0 1px 1px rgba(0,0,0,0.2)",
      transition: "background var(--dur-fast), border-color var(--dur-fast)"
    }
  }, checked && /*#__PURE__*/React.createElement("i", {
    className: "ph-bold ph-check",
    style: {
      fontSize: 11,
      color: "#fff"
    }
  }));
  if (!label) {
    return /*#__PURE__*/React.createElement("button", {
      type: "button",
      role: "checkbox",
      "aria-checked": checked,
      disabled: disabled,
      onClick: () => !disabled && onChange && onChange(!checked),
      style: {
        background: "none",
        border: "none",
        padding: 0,
        cursor: disabled ? "default" : "pointer",
        opacity: disabled ? 0.4 : 1,
        ...style
      }
    }, box);
  }
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 8,
      cursor: disabled ? "default" : "pointer",
      opacity: disabled ? 0.4 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "checkbox",
    "aria-checked": checked,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      background: "none",
      border: "none",
      padding: 0,
      cursor: "inherit"
    }
  }, box), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-sans)",
      fontSize: 12,
      fontWeight: "var(--w-light)",
      color: "var(--text-secondary)"
    }
  }, label));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/controls/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Icon — thin wrapper over Phosphor Icons (web font), the closest CDN stand-in
 * for the app's native SF Symbols. The host page must load the Phosphor web font
 * (see any card/kit <head>). `weight` maps to Phosphor weights; the app's default
 * "hierarchical, solid" feel maps best to "fill" for active glyphs and "regular"
 * for idle ones.
 */
function Icon({
  name,
  weight = "regular",
  size = 16,
  color = "currentColor",
  style = {},
  ...rest
}) {
  const cls = weight === "regular" ? `ph ph-${name}` : `ph-${weight} ph-${name}`;
  return /*#__PURE__*/React.createElement("i", _extends({
    className: cls,
    style: {
      fontSize: size,
      color,
      lineHeight: 1,
      display: "inline-flex",
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Icon.jsx", error: String((e && e.message) || e) }); }

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Button — EXP's primary action control. Default variant is Liquid Glass with an
 * accent tint; secondary is a neutral glass; ghost is borderless. Matches the
 * VISUAL-HANDOFF "Primary button" spec (radius 8, lit edge, sheen, AA focus).
 */
function Button({
  children,
  variant = "primary",
  // primary | secondary | ghost | destructive
  size = "md",
  // sm | md | lg
  icon,
  // optional Phosphor icon name (leading)
  iconWeight = "bold",
  disabled = false,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [press, setPress] = React.useState(false);
  const sizes = {
    sm: {
      h: 22,
      px: 10,
      fs: 12,
      gap: 5
    },
    md: {
      h: 30,
      px: 14,
      fs: 13,
      gap: 6
    },
    lg: {
      h: 36,
      px: 18,
      fs: 14,
      gap: 7
    }
  }[size];
  const base = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: sizes.gap,
    height: sizes.h,
    padding: `0 ${sizes.px}px`,
    borderRadius: "var(--radius-button)",
    fontFamily: "var(--font-sans)",
    fontSize: sizes.fs,
    fontWeight: "var(--w-medium)",
    letterSpacing: "-0.01em",
    cursor: disabled ? "default" : "pointer",
    border: "1px solid transparent",
    whiteSpace: "nowrap",
    userSelect: "none",
    outline: "none",
    transition: "background var(--dur-fast) var(--ease-standard), transform var(--dur-fast) var(--ease-standard), box-shadow var(--dur-fast)",
    transform: press && !disabled ? "translateY(0.5px) scale(0.985)" : "none",
    opacity: disabled ? 0.4 : 1
  };
  const variants = {
    primary: {
      background: press ? "var(--accent-press)" : hover ? "var(--accent-hover)" : "var(--accent)",
      color: "var(--text-on-accent)",
      borderColor: "rgba(255,255,255,0.18)",
      boxShadow: press ? "var(--shadow-1)" : "var(--shadow-2), inset 0 1px 0 rgba(255,255,255,0.25)"
    },
    secondary: {
      background: hover ? "var(--row-active)" : "var(--surface-field)",
      color: "var(--text-primary)",
      borderColor: "var(--border-glass)",
      boxShadow: "var(--glass-inner-hi)"
    },
    ghost: {
      background: hover ? "var(--row-hover)" : "transparent",
      color: "var(--text-primary)",
      borderColor: "transparent"
    },
    destructive: {
      background: press ? "#c8352c" : hover ? "#ff5a50" : "var(--red)",
      color: "#fff",
      borderColor: "rgba(255,255,255,0.18)",
      boxShadow: "var(--shadow-1)"
    }
  }[variant];
  const focusRing = {
    boxShadow: `${variants.boxShadow || ""}, var(--glow-accent)`
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    onClick: disabled ? undefined : onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setPress(false);
    },
    onMouseDown: () => setPress(true),
    onMouseUp: () => setPress(false),
    onFocus: e => {
      if (!disabled) Object.assign(e.currentTarget.style, focusRing);
    },
    onBlur: e => {
      e.currentTarget.style.boxShadow = variants.boxShadow || "none";
    },
    style: {
      ...base,
      ...variants,
      ...style
    }
  }, rest), icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    weight: iconWeight,
    size: sizes.fs + 1
  }), children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * IconButton — square, borderless glyph button for toolbars, inspector rows, and
 * the tools strip. Active state uses the accent-tinted fill (accent @ 0.22, the
 * app's tool-button highlight); hover is a soft neutral wash.
 */
function IconButton({
  icon,
  weight,
  // overrides; defaults derived from active
  active = false,
  size = "md",
  // sm | md | lg
  disabled = false,
  title,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const dim = {
    sm: 22,
    md: 28,
    lg: 30
  }[size];
  const glyph = {
    sm: 13,
    md: 15,
    lg: 16
  }[size];
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    title: title,
    "aria-label": title,
    "aria-pressed": active,
    disabled: disabled,
    onClick: disabled ? undefined : onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      width: dim,
      height: dim,
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      borderRadius: "var(--radius-tool)",
      border: "none",
      cursor: disabled ? "default" : "pointer",
      background: active ? "var(--accent-subtle-2)" : hover ? "var(--row-hover)" : "transparent",
      color: active ? "var(--text-accent)" : disabled ? "var(--text-quaternary)" : "var(--text-primary)",
      transition: "background var(--dur-fast) var(--ease-standard), color var(--dur-fast)",
      outline: "none",
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    weight: weight || (active ? "fill" : "regular"),
    size: glyph
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/controls/SegmentedControl.jsx
try { (() => {
/**
 * SegmentedControl — the app's pill toggle (e.g. "Selection / Artboard", row vs
 * column, Gap vs Space Between). Selected segment shows the accent fill; the
 * track is an inset glass groove.
 */
function SegmentedControl({
  options,
  // [{ value, label?, icon? }] or ["a","b"]
  value,
  onChange,
  size = "md",
  // sm | md
  fill = "accent",
  // accent | neutral
  style = {}
}) {
  const opts = options.map(o => typeof o === "string" ? {
    value: o,
    label: o
  } : o);
  const h = size === "sm" ? 22 : 28;
  const fs = size === "sm" ? 11 : 12.5;
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: "inline-flex",
      height: h,
      padding: 2,
      gap: 2,
      background: "var(--surface-field)",
      borderRadius: "var(--radius-control)",
      border: "1px solid var(--border-soft)",
      boxShadow: "inset 0 1px 2px rgba(0,0,0,0.25)",
      ...style
    }
  }, opts.map(o => {
    const sel = o.value === value;
    const selBg = fill === "accent" ? "var(--accent)" : "var(--n-400)";
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      role: "tab",
      "aria-selected": sel,
      onClick: () => onChange && onChange(o.value),
      style: {
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 5,
        height: h - 4,
        padding: "0 12px",
        border: "none",
        cursor: "pointer",
        borderRadius: "calc(var(--radius-control) - 2px)",
        fontFamily: "var(--font-sans)",
        fontSize: fs,
        fontWeight: sel ? "var(--w-medium)" : "var(--w-light)",
        background: sel ? selBg : "transparent",
        color: sel ? fill === "accent" ? "var(--text-on-accent)" : "var(--text-primary)" : "var(--text-secondary)",
        boxShadow: sel ? "var(--shadow-1), inset 0 1px 0 rgba(255,255,255,0.2)" : "none",
        transition: "background var(--dur-fast) var(--ease-standard), color var(--dur-fast)",
        whiteSpace: "nowrap"
      }
    }, o.icon && /*#__PURE__*/React.createElement("i", {
      className: `ph-bold ph-${o.icon}`,
      style: {
        fontSize: fs + 1
      }
    }), o.label);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// components/controls/Slider.jsx
try { (() => {
/**
 * Slider — the inspector's zoom/value slider. Thin track, accent-filled left of
 * the knob, round draggable thumb. Controlled via value/min/max.
 */
function Slider({
  value,
  min = 0,
  max = 100,
  step = 1,
  onChange,
  style = {}
}) {
  const ref = React.useRef(null);
  const pct = Math.max(0, Math.min(1, (value - min) / (max - min)));
  const setFromClientX = clientX => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const t = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
    const raw = min + t * (max - min);
    const snapped = Math.round(raw / step) * step;
    onChange && onChange(Math.max(min, Math.min(max, snapped)));
  };
  const onDown = e => {
    setFromClientX(e.clientX);
    const move = ev => setFromClientX(ev.clientX);
    const up = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };
  return /*#__PURE__*/React.createElement("div", {
    ref: ref,
    onMouseDown: onDown,
    style: {
      position: "relative",
      height: 18,
      display: "flex",
      alignItems: "center",
      cursor: "pointer",
      flex: 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      height: 3,
      borderRadius: 999,
      background: "var(--n-400)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      width: `${pct * 100}%`,
      height: 3,
      borderRadius: 999,
      background: "var(--accent)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: `calc(${pct * 100}% - 7px)`,
      width: 14,
      height: 14,
      borderRadius: 999,
      background: "#fff",
      boxShadow: "0 1px 3px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(0,0,0,0.3)"
    }
  }));
}
Object.assign(__ds_scope, { Slider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Slider.jsx", error: String((e && e.message) || e) }); }

// components/controls/Switch.jsx
try { (() => {
/**
 * Switch — macOS-style toggle. The app uses `.controlSize(.mini)` switches in the
 * inspector (Auto Layout / Auto Padding), so `mini` is the default size here.
 */
function Switch({
  checked = false,
  onChange,
  disabled = false,
  size = "mini",
  style = {}
}) {
  const dims = {
    mini: {
      w: 26,
      h: 15,
      k: 11
    },
    small: {
      w: 32,
      h: 19,
      k: 15
    }
  }[size];
  const pad = (dims.h - dims.k) / 2;
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "switch",
    "aria-checked": checked,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      width: dims.w,
      height: dims.h,
      borderRadius: 999,
      border: "none",
      padding: 0,
      cursor: disabled ? "default" : "pointer",
      position: "relative",
      background: checked ? "var(--accent)" : "var(--n-400)",
      boxShadow: checked ? "inset 0 1px 2px rgba(0,0,0,0.2)" : "inset 0 1px 2px rgba(0,0,0,0.3)",
      opacity: disabled ? 0.4 : 1,
      transition: "background var(--dur-base) var(--ease-standard)",
      outline: "none"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: pad,
      left: checked ? dims.w - dims.k - pad : pad,
      width: dims.k,
      height: dims.k,
      borderRadius: 999,
      background: "#fff",
      boxShadow: "0 1px 2px rgba(0,0,0,0.35)",
      transition: "left var(--dur-base) var(--ease-emphasis)"
    }
  }));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Switch.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Badge.jsx
try { (() => {
/**
 * Badge — a small status/count pill. `dot` adds a leading status dot (the lime
 * "online", or any semantic colour). Used for component counts ("8 layers"),
 * status, and the live brand-lime indicator.
 */
const TONES = {
  neutral: {
    bg: "var(--surface-card)",
    fg: "var(--text-secondary)",
    bd: "var(--border-soft)"
  },
  accent: {
    bg: "var(--accent-subtle)",
    fg: "var(--text-accent)",
    bd: "transparent"
  },
  brand: {
    bg: "rgba(76,230,46,0.14)",
    fg: "var(--text-brand)",
    bd: "transparent"
  },
  red: {
    bg: "rgba(255,69,58,0.16)",
    fg: "#ff6a60",
    bd: "transparent"
  }
};
function Badge({
  children,
  tone = "neutral",
  dot = false,
  dotColor,
  style = {}
}) {
  const t = TONES[tone] || TONES.neutral;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 5,
      height: 18,
      padding: "0 7px",
      borderRadius: "var(--radius-pill)",
      background: t.bg,
      border: `1px solid ${t.bd}`,
      color: t.fg,
      fontFamily: "var(--font-sans)",
      fontSize: 10.5,
      fontWeight: "var(--w-medium)",
      lineHeight: 1,
      fontVariantNumeric: "tabular-nums",
      whiteSpace: "nowrap",
      ...style
    }
  }, dot && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      height: 6,
      borderRadius: 999,
      background: dotColor || (tone === "brand" ? "var(--brand-lime)" : "currentColor"),
      boxShadow: tone === "brand" ? "var(--glow-lime)" : "none"
    }
  }), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Badge.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Tooltip.jsx
try { (() => {
/**
 * Tooltip — the macOS help bubble shown on hover. A glass-thin popover with the
 * label and an optional keyboard hint (e.g. "Select  V"). Wrap any trigger.
 */
function Tooltip({
  label,
  shortcut,
  side = "top",
  children,
  style = {}
}) {
  const [show, setShow] = React.useState(false);
  const pos = {
    top: {
      bottom: "calc(100% + 6px)",
      left: "50%",
      transform: "translateX(-50%)"
    },
    bottom: {
      top: "calc(100% + 6px)",
      left: "50%",
      transform: "translateX(-50%)"
    },
    right: {
      left: "calc(100% + 6px)",
      top: "50%",
      transform: "translateY(-50%)"
    },
    left: {
      right: "calc(100% + 6px)",
      top: "50%",
      transform: "translateY(-50%)"
    }
  }[side];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      position: "relative",
      display: "inline-flex",
      ...style
    },
    onMouseEnter: () => setShow(true),
    onMouseLeave: () => setShow(false)
  }, children, show && /*#__PURE__*/React.createElement("span", {
    className: "glass-thin glass-edge",
    style: {
      position: "absolute",
      ...pos,
      zIndex: 100,
      display: "inline-flex",
      alignItems: "center",
      gap: 7,
      padding: "4px 8px",
      borderRadius: 6,
      boxShadow: "var(--shadow-popover)",
      fontFamily: "var(--font-sans)",
      fontSize: 11,
      fontWeight: "var(--w-light)",
      color: "var(--text-primary)",
      whiteSpace: "nowrap",
      pointerEvents: "none"
    }
  }, label, shortcut && /*#__PURE__*/React.createElement("kbd", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: 10,
      color: "var(--text-tertiary)",
      background: "var(--surface-field)",
      padding: "1px 4px",
      borderRadius: 3,
      border: "1px solid var(--border-soft)"
    }
  }, shortcut)));
}
Object.assign(__ds_scope, { Tooltip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Tooltip.jsx", error: String((e && e.message) || e) }); }

// components/inputs/ColorWell.jsx
try { (() => {
/**
 * ColorWell — the Fill / Stroke swatch in the inspector. Shows the colour over a
 * checkerboard (so alpha reads), with an optional trailing label. Click is wired
 * via onClick (host opens its own colour popover). Covers both the app's ColorWell
 * (stroke) and PaintWell (fill) — pass a CSS gradient string for a gradient fill.
 */
function ColorWell({
  color = "#ffffff",
  label,
  onClick,
  size = "md",
  style = {}
}) {
  const dims = {
    sm: {
      w: 40,
      h: 18
    },
    md: {
      w: 52,
      h: 22
    }
  }[size];
  const swatch = /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    style: {
      width: dims.w,
      height: dims.h,
      padding: 0,
      borderRadius: 5,
      cursor: "pointer",
      border: "1px solid var(--border-strong)",
      overflow: "hidden",
      position: "relative",
      // checkerboard under transparent colours
      backgroundImage: "linear-gradient(45deg,#999 25%,transparent 25%),linear-gradient(-45deg,#999 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#999 75%),linear-gradient(-45deg,transparent 75%,#999 75%)",
      backgroundSize: "8px 8px",
      backgroundPosition: "0 0,0 4px,4px -4px,-4px 0px",
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      inset: 0,
      background: color
    }
  }));
  if (!label) return /*#__PURE__*/React.createElement("span", {
    style: style
  }, swatch);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 8,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-sans)",
      fontSize: 12,
      fontWeight: "var(--w-light)",
      color: "var(--text-secondary)"
    }
  }, label), swatch);
}
Object.assign(__ds_scope, { ColorWell });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/ColorWell.jsx", error: String((e && e.message) || e) }); }

// components/inputs/NumericField.jsx
try { (() => {
/**
 * NumericField — the inspector's X/Y/W/H/opacity field: an optional single-letter
 * label, a right-aligned monospaced-digit value, and a trailing unit. Drag-on-
 * label scrubbing is omitted (cosmetic kit) but click-to-edit works.
 */
function NumericField({
  label,
  value,
  onChange,
  unit,
  min,
  max,
  width = 56,
  disabled = false,
  style = {}
}) {
  const [focus, setFocus] = React.useState(false);
  const commit = raw => {
    let n = parseFloat(raw);
    if (Number.isNaN(n)) return;
    if (min != null) n = Math.max(min, n);
    if (max != null) n = Math.min(max, n);
    onChange && onChange(n);
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 4,
      ...style
    }
  }, label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-sans)",
      fontSize: 12,
      fontWeight: "var(--w-light)",
      color: "var(--text-tertiary)",
      width: 12,
      textAlign: "left",
      flex: "none"
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      width,
      flex: "none"
    }
  }, /*#__PURE__*/React.createElement("input", {
    type: "text",
    defaultValue: value,
    key: value,
    disabled: disabled,
    onFocus: () => setFocus(true),
    onBlur: e => {
      setFocus(false);
      commit(e.target.value);
    },
    onKeyDown: e => {
      if (e.key === "Enter") e.currentTarget.blur();
    },
    style: {
      width: "100%",
      boxSizing: "border-box",
      height: "var(--control-h)",
      padding: unit ? "0 18px 0 8px" : "0 8px",
      borderRadius: "var(--radius-field)",
      background: focus ? "var(--surface-field-focus)" : "var(--surface-field)",
      border: `1px solid ${focus ? "var(--accent)" : "var(--border-strong)"}`,
      boxShadow: focus ? "0 0 0 3px var(--accent-subtle)" : "inset 0 1px 1px rgba(0,0,0,0.18)",
      color: "var(--text-primary)",
      textAlign: "right",
      fontFamily: "var(--font-sans)",
      fontSize: 12,
      fontVariantNumeric: "tabular-nums",
      outline: "none",
      opacity: disabled ? 0.5 : 1,
      transition: "border-color var(--dur-fast), box-shadow var(--dur-fast)"
    }
  }), unit && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      right: 7,
      top: "50%",
      transform: "translateY(-50%)",
      fontFamily: "var(--font-sans)",
      fontSize: 11,
      color: "var(--text-tertiary)",
      pointerEvents: "none"
    }
  }, unit)));
}
Object.assign(__ds_scope, { NumericField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/NumericField.jsx", error: String((e && e.message) || e) }); }

// components/inputs/Select.jsx
try { (() => {
/**
 * Select — the inspector's dropdown (Blend mode, line-height unit). A glass-field
 * trigger with a chevron; opens a glass popover list. Controlled by value.
 */
function Select({
  options,
  value,
  onChange,
  width,
  disabled = false,
  style = {}
}) {
  const opts = options.map(o => typeof o === "string" ? {
    value: o,
    label: o
  } : o);
  const [open, setOpen] = React.useState(false);
  const [hover, setHover] = React.useState(false);
  const ref = React.useRef(null);
  const current = opts.find(o => o.value === value) || opts[0];
  React.useEffect(() => {
    if (!open) return;
    const close = e => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    window.addEventListener("mousedown", close);
    return () => window.removeEventListener("mousedown", close);
  }, [open]);
  return /*#__PURE__*/React.createElement("div", {
    ref: ref,
    style: {
      position: "relative",
      width: width || "auto",
      ...style
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    disabled: disabled,
    onClick: () => setOpen(o => !o),
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      width: "100%",
      boxSizing: "border-box",
      height: "var(--control-h)",
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 8,
      padding: "0 6px 0 8px",
      borderRadius: "var(--radius-field)",
      background: hover ? "var(--surface-field-focus)" : "var(--surface-field)",
      border: "1px solid var(--border-strong)",
      cursor: disabled ? "default" : "pointer",
      color: "var(--text-primary)",
      fontFamily: "var(--font-sans)",
      fontSize: 12,
      fontWeight: "var(--w-light)",
      outline: "none",
      opacity: disabled ? 0.5 : 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, current?.label), /*#__PURE__*/React.createElement("i", {
    className: "ph-bold ph-caret-up-down",
    style: {
      fontSize: 11,
      color: "var(--text-tertiary)"
    }
  })), open && /*#__PURE__*/React.createElement("div", {
    className: "glass-medium glass-edge",
    style: {
      position: "absolute",
      top: "calc(100% + 4px)",
      left: 0,
      minWidth: "100%",
      zIndex: 50,
      padding: 4,
      borderRadius: "var(--radius-row)",
      boxShadow: "var(--shadow-popover)"
    }
  }, opts.map(o => {
    const sel = o.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      type: "button",
      onClick: () => {
        onChange && onChange(o.value);
        setOpen(false);
      },
      style: {
        width: "100%",
        display: "flex",
        alignItems: "center",
        gap: 8,
        height: 24,
        padding: "0 8px",
        border: "none",
        cursor: "pointer",
        textAlign: "left",
        borderRadius: 4,
        background: sel ? "var(--accent)" : "transparent",
        color: sel ? "#fff" : "var(--text-primary)",
        fontFamily: "var(--font-sans)",
        fontSize: 12,
        fontWeight: "var(--w-light)",
        whiteSpace: "nowrap"
      },
      onMouseEnter: e => {
        if (!sel) e.currentTarget.style.background = "var(--row-hover)";
      },
      onMouseLeave: e => {
        if (!sel) e.currentTarget.style.background = "transparent";
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 12,
        flex: "none"
      }
    }, sel && /*#__PURE__*/React.createElement("i", {
      className: "ph-bold ph-check",
      style: {
        fontSize: 11
      }
    })), o.label);
  })));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/Select.jsx", error: String((e && e.message) || e) }); }

// components/inputs/TextField.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * TextField — rounded-border text input. Used for the layer/artboard name and any
 * single-line string. Focus shows the accent ring.
 */
function TextField({
  value,
  onChange,
  placeholder,
  weight = "light",
  align = "left",
  disabled = false,
  monospace = false,
  style = {},
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  return /*#__PURE__*/React.createElement("input", _extends({
    type: "text",
    value: value,
    placeholder: placeholder,
    disabled: disabled,
    onChange: e => onChange && onChange(e.target.value),
    onFocus: () => setFocus(true),
    onBlur: () => setFocus(false),
    style: {
      width: "100%",
      boxSizing: "border-box",
      height: "var(--control-h)",
      padding: "0 8px",
      borderRadius: "var(--radius-field)",
      background: focus ? "var(--surface-field-focus)" : "var(--surface-field)",
      border: `1px solid ${focus ? "var(--accent)" : "var(--border-strong)"}`,
      boxShadow: focus ? "0 0 0 3px var(--accent-subtle)" : "inset 0 1px 1px rgba(0,0,0,0.18)",
      color: "var(--text-primary)",
      textAlign: align,
      fontFamily: monospace ? "var(--font-mono)" : "var(--font-sans)",
      fontSize: 12,
      fontWeight: `var(--w-${weight})`,
      outline: "none",
      transition: "border-color var(--dur-fast), box-shadow var(--dur-fast), background var(--dur-fast)",
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/inputs/TextField.jsx", error: String((e && e.message) || e) }); }

// components/structure/Divider.jsx
try { (() => {
/** Divider — a hairline separator (separatorColor analog). Horizontal by default. */
function Divider({
  vertical = false,
  inset = 0,
  style = {}
}) {
  return vertical ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      alignSelf: "stretch",
      background: "var(--hairline)",
      margin: `${inset}px 0`,
      flex: "none",
      ...style
    }
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      height: 1,
      background: "var(--hairline)",
      margin: `0 ${inset}px`,
      ...style
    }
  });
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/structure/Divider.jsx", error: String((e && e.message) || e) }); }

// components/structure/LayerRow.jsx
try { (() => {
/**
 * LayerRow — one row in the Layers panel. Anatomy: indent · disclosure chevron ·
 * eye (visibility) · type glyph · name (SF Compact) · lock. Selected rows take the
 * accent-subtle fill with an accent left edge; locked rows dim. Matches the app's
 * layer tree exactly (icons map to node kinds).
 */
const KIND_ICON = {
  text: "text-aa",
  image: "image",
  component: "squares-four",
  instance: "squares-four",
  group: "folder-simple",
  rectangle: "square",
  ellipse: "circle",
  line: "line-segment",
  path: "scribble-loop",
  polygon: "triangle",
  artboard: "frame-corners"
};
function LayerRow({
  name,
  kind = "rectangle",
  depth = 0,
  selected = false,
  hidden = false,
  locked = false,
  expandable = false,
  expanded = false,
  onToggle,
  onSelect,
  onToggleHidden,
  onToggleLock,
  style = {}
}) {
  const [hover, setHover] = React.useState(false);
  const icon = KIND_ICON[kind] || "square";
  return /*#__PURE__*/React.createElement("div", {
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    onClick: onSelect,
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6,
      height: 28,
      paddingRight: 8,
      paddingLeft: 6 + depth * 15,
      cursor: "default",
      position: "relative",
      background: selected ? "var(--accent-subtle)" : hover ? "var(--row-hover)" : "transparent",
      boxShadow: selected ? "inset 2px 0 0 var(--accent)" : "none",
      opacity: hidden ? 0.45 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: e => {
      e.stopPropagation();
      onToggle && onToggle();
    },
    style: {
      width: 12,
      flex: "none",
      background: "none",
      border: "none",
      padding: 0,
      cursor: "pointer",
      color: "var(--text-tertiary)",
      visibility: expandable ? "visible" : "hidden"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph-bold ph-caret-right",
    style: {
      fontSize: 10,
      display: "inline-block",
      transform: expanded ? "rotate(90deg)" : "none",
      transition: "transform var(--dur-fast)"
    }
  })), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: e => {
      e.stopPropagation();
      onToggleHidden && onToggleHidden();
    },
    title: hidden ? "Show" : "Hide",
    style: {
      width: 16,
      flex: "none",
      background: "none",
      border: "none",
      padding: 0,
      cursor: "pointer",
      color: hover || hidden ? "var(--text-secondary)" : "var(--text-tertiary)"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: hidden ? "ph ph-eye-slash" : "ph ph-eye",
    style: {
      fontSize: 13
    }
  })), /*#__PURE__*/React.createElement("i", {
    className: `ph ph-${icon}`,
    style: {
      fontSize: 13,
      flex: "none",
      color: selected ? "var(--text-accent)" : "var(--text-tertiary)"
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      fontFamily: "var(--font-condensed)",
      fontSize: 12,
      fontWeight: selected ? "var(--w-regular)" : "var(--w-light)",
      color: selected ? "var(--text-primary)" : "var(--text-primary)",
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, name), /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: e => {
      e.stopPropagation();
      onToggleLock && onToggleLock();
    },
    title: locked ? "Unlock" : "Lock",
    style: {
      width: 16,
      flex: "none",
      background: "none",
      border: "none",
      padding: 0,
      cursor: "pointer",
      opacity: locked || hover ? 1 : 0,
      color: locked ? "var(--text-secondary)" : "var(--text-tertiary)",
      transition: "opacity var(--dur-fast)"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: locked ? "ph-fill ph-lock-simple" : "ph ph-lock-simple-open",
    style: {
      fontSize: 13
    }
  })));
}
Object.assign(__ds_scope, { LayerRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/structure/LayerRow.jsx", error: String((e && e.message) || e) }); }

// components/structure/Panel.jsx
try { (() => {
/**
 * Panel — a Liquid Glass dock/floating panel shell. Wraps a PanelHeader-style bar
 * (icon + uppercase title + optional detach affordance) over a content area. The
 * default material is `medium` (the dock panel); pass `material="thin"` for an
 * inline tray.
 */
function Panel({
  title,
  icon = "stack-simple",
  material = "medium",
  actions,
  detachable = true,
  accentTitle = false,
  children,
  style = {},
  bodyStyle = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `glass-${material} glass-edge`,
    style: {
      display: "flex",
      flexDirection: "column",
      borderRadius: "var(--radius-panel)",
      overflow: "hidden",
      minWidth: 220,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      height: "var(--panel-header-height)",
      padding: "0 10px",
      borderBottom: "1px solid var(--hairline)",
      flex: "none",
      position: "relative",
      zIndex: 1
    }
  }, icon && /*#__PURE__*/React.createElement("i", {
    className: `ph-fill ph-${icon}`,
    style: {
      fontSize: 15,
      color: accentTitle ? "var(--text-accent)" : "var(--text-secondary)"
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-sans)",
      fontSize: "var(--t-base)",
      fontWeight: "var(--w-regular)",
      textTransform: "uppercase",
      letterSpacing: "var(--tr-caps)",
      color: accentTitle ? "var(--text-accent)" : "var(--text-primary)",
      flex: 1
    }
  }, title), actions, detachable && /*#__PURE__*/React.createElement("i", {
    className: "ph ph-arrow-square-out",
    style: {
      fontSize: 14,
      color: "var(--text-tertiary)",
      cursor: "pointer"
    },
    title: "Detach panel"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: "auto",
      position: "relative",
      zIndex: 1,
      ...bodyStyle
    }
  }, children));
}
Object.assign(__ds_scope, { Panel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/structure/Panel.jsx", error: String((e && e.message) || e) }); }

// components/structure/SectionHeader.jsx
try { (() => {
/**
 * SectionHeader — an inspector section label ("Effects", "Layout Grids", "Stroke")
 * in ultralight secondary type, with an optional trailing action (a + or chevron).
 */
function SectionHeader({
  title,
  action,
  onAction,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "10px var(--panel-pad-h) 4px",
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-display)",
      fontSize: "var(--t-mini)",
      fontWeight: "var(--w-ultralight)",
      textTransform: "uppercase",
      letterSpacing: "var(--tr-wide)",
      color: "var(--text-secondary)"
    }
  }, title), action && /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    "aria-label": `${title} action`,
    style: {
      background: "none",
      border: "none",
      padding: 2,
      cursor: "pointer",
      color: "var(--text-tertiary)",
      display: "inline-flex"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `ph ph-${action}`,
    style: {
      fontSize: 14
    }
  })));
}
Object.assign(__ds_scope, { SectionHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/structure/SectionHeader.jsx", error: String((e && e.message) || e) }); }

// components/structure/ToolStrip.jsx
try { (() => {
/**
 * ToolStrip — the fixed vertical tools rail pinned to the window's left edge.
 * Thin glass, grouped tools separated by hairlines, active tool accent-tinted.
 * Default tools mirror the app's Tool enum.
 */
const DEFAULT_GROUPS = [[{
  id: "select",
  icon: "cursor",
  label: "Select"
}, {
  id: "node",
  icon: "bezier-curve",
  label: "Edit Points"
}], [{
  id: "rectangle",
  icon: "square",
  label: "Rectangle"
}, {
  id: "ellipse",
  icon: "circle",
  label: "Ellipse"
}, {
  id: "polygon",
  icon: "triangle",
  label: "Polygon"
}, {
  id: "line",
  icon: "line-segment",
  label: "Line"
}], [{
  id: "pen",
  icon: "pen-nib",
  label: "Pen"
}, {
  id: "text",
  icon: "text-t",
  label: "Text"
}]];
function ToolStrip({
  groups = DEFAULT_GROUPS,
  active = "select",
  onSelect,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "glass-thin",
    style: {
      width: "var(--tools-strip-width)",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 4,
      padding: "8px 0",
      borderRight: "1px solid var(--hairline)",
      ...style
    }
  }, groups.map((group, gi) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: gi
  }, gi > 0 && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 22,
      height: 1,
      background: "var(--hairline)",
      margin: "4px 0"
    }
  }), group.map(t => /*#__PURE__*/React.createElement(__ds_scope.IconButton, {
    key: t.id,
    icon: t.icon,
    title: t.label,
    active: active === t.id,
    size: "lg",
    onClick: () => onSelect && onSelect(t.id)
  })))));
}
Object.assign(__ds_scope, { ToolStrip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/structure/ToolStrip.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/Canvas.jsx
try { (() => {
// Canvas — the undesigned center surface: top + corner rulers, the dark "wall",
// and the white artboard with its label + selection chrome. Layers render as
// simple cosmetic blocks; the selected one shows handles. Per the brief the
// canvas itself stays minimal and token-isolated (--canvas-*).
const NS = window.EXPDesignDesignSystem_fb82b2;
function Ruler({
  horizontal
}) {
  const ticks = [];
  for (let i = 0; i < 28; i++) {
    const major = i % 5 === 0;
    ticks.push(/*#__PURE__*/React.createElement("div", {
      key: i,
      style: {
        position: "absolute",
        ...(horizontal ? {
          left: `${i * 60}px`,
          top: major ? 8 : 13,
          width: 1,
          height: major ? 12 : 7
        } : {
          top: `${i * 60}px`,
          left: major ? 8 : 13,
          height: 1,
          width: major ? 12 : 7
        }),
        background: "var(--canvas-ruler-tick)"
      }
    }, major && /*#__PURE__*/React.createElement("span", {
      style: {
        position: "absolute",
        fontSize: 9,
        fontFamily: "var(--font-mono)",
        color: "var(--canvas-ruler-tick)",
        whiteSpace: "nowrap",
        ...(horizontal ? {
          left: 3,
          top: -9
        } : {
          top: 2,
          left: -2,
          writingMode: "vertical-rl"
        })
      }
    }, i * 100 - 300)));
  }
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      background: "var(--canvas-ruler-bg)",
      backdropFilter: "blur(8px)",
      WebkitBackdropFilter: "blur(8px)",
      ...(horizontal ? {
        top: 0,
        left: "var(--ruler-size)",
        right: 0,
        height: "var(--ruler-size)",
        borderBottom: "1px solid var(--hairline)"
      } : {
        top: "var(--ruler-size)",
        left: 0,
        bottom: 0,
        width: "var(--ruler-size)",
        borderRight: "1px solid var(--hairline)"
      }),
      zIndex: 2
    }
  }, ticks);
}
function LayerBlock({
  layer,
  selected,
  scale,
  onSelect
}) {
  if (layer.X == null) return null;
  const isText = layer.kind === "text";
  const isEllipse = layer.kind === "ellipse";
  return /*#__PURE__*/React.createElement("div", {
    onClick: e => {
      e.stopPropagation();
      onSelect(layer.id);
    },
    style: {
      position: "absolute",
      left: layer.X * scale,
      top: layer.Y * scale,
      width: layer.W * scale,
      height: layer.H * scale,
      transform: `rotate(${layer.rot || 0}deg)`,
      opacity: (layer.opacity ?? 100) / 100,
      background: isText ? "transparent" : layer.fill,
      borderRadius: isEllipse ? "50%" : layer.kind === "component" ? 8 : 2,
      display: isText ? "flex" : "block",
      alignItems: "center",
      color: "#1a1a1c",
      fontSize: 15 * scale,
      fontWeight: "var(--w-light)",
      cursor: "pointer",
      outline: selected ? "1.5px solid var(--canvas-selection)" : "none",
      boxShadow: selected ? "0 0 0 1px rgba(10,132,255,0.3)" : "none",
      visibility: layer.hidden ? "hidden" : "visible"
    }
  }, isText && /*#__PURE__*/React.createElement("span", null, "a text layer."), selected && ["nw", "ne", "sw", "se"].map(h => /*#__PURE__*/React.createElement("span", {
    key: h,
    style: {
      position: "absolute",
      width: 7,
      height: 7,
      background: "#fff",
      border: "1px solid var(--canvas-selection)",
      borderRadius: 1,
      top: h[0] === "n" ? -4 : "auto",
      bottom: h[0] === "s" ? -4 : "auto",
      left: h[1] === "w" ? -4 : "auto",
      right: h[1] === "e" ? -4 : "auto"
    }
  })));
}
function Canvas({
  doc,
  selected,
  onSelect,
  zoom
}) {
  const ab = doc.artboards[0];
  const scale = 0.62 * (zoom / 94);
  return /*#__PURE__*/React.createElement("div", {
    onClick: () => onSelect(null),
    style: {
      position: "relative",
      flex: 1,
      overflow: "hidden",
      background: "var(--canvas-bg)",
      minWidth: 360
    }
  }, /*#__PURE__*/React.createElement(Ruler, {
    horizontal: true
  }), /*#__PURE__*/React.createElement(Ruler, null), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: "var(--ruler-size) 0 0 var(--ruler-size)",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: "50%",
      top: 70,
      transform: "translateX(-50%)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6,
      marginBottom: 8,
      color: selected === "ab" ? "var(--text-accent)" : "var(--text-secondary)"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph ph-frame-corners",
    style: {
      fontSize: 13
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      fontWeight: "var(--w-medium)"
    }
  }, ab.name)), /*#__PURE__*/React.createElement("div", {
    onClick: e => {
      e.stopPropagation();
      onSelect("ab");
    },
    style: {
      position: "relative",
      width: ab.w * scale,
      height: ab.h * scale,
      background: "var(--canvas-artboard)",
      cursor: "pointer",
      outline: selected === "ab" ? "1.5px solid var(--canvas-selection)" : "none",
      boxShadow: "0 8px 40px rgba(0,0,0,0.4)"
    }
  }, doc.layers.map(l => /*#__PURE__*/React.createElement(LayerBlock, {
    key: l.id,
    layer: l,
    selected: selected === l.id,
    scale: scale,
    onSelect: onSelect
  }))))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: 0,
      left: 0,
      width: "var(--ruler-size)",
      height: "var(--ruler-size)",
      background: "var(--canvas-ruler-bg)",
      borderRight: "1px solid var(--hairline)",
      borderBottom: "1px solid var(--hairline)",
      zIndex: 3
    }
  }));
}
window.Canvas = Canvas;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/Canvas.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/EditorShell.jsx
try { (() => {
// EditorShell — composes the whole three-pane editor and owns the interactive
// state (tool, selection, zoom, appearance, panel visibility).
const NS = window.EXPDesignDesignSystem_fb82b2;
function EditorShell() {
  const {
    ToolStrip
  } = NS;
  const [doc, setDoc] = React.useState(window.EXP_DOC);
  const [tool, setTool] = React.useState("select");
  const [selected, setSelected] = React.useState("c1");
  const [zoom, setZoom] = React.useState(window.EXP_DOC.zoom);
  const [appearance, setAppearance] = React.useState("exp-dark");
  const [panels, setPanels] = React.useState({
    left: true,
    right: true
  });
  React.useEffect(() => {
    document.documentElement.className = appearance;
  }, [appearance]);
  const update = patch => {
    setDoc(d => ({
      ...d,
      layers: d.layers.map(l => l.id === selected ? {
        ...l,
        ...patch
      } : l)
    }));
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      height: "100vh",
      background: "var(--surface-window)",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement(window.TopBar, {
    doc: doc,
    zoom: zoom,
    setZoom: setZoom,
    appearance: appearance,
    setAppearance: setAppearance,
    panels: panels,
    setPanels: setPanels
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flex: 1,
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement(ToolStrip, {
    active: tool,
    onSelect: setTool
  }), panels.left && /*#__PURE__*/React.createElement("div", {
    style: {
      width: "var(--dock-left-width)",
      flex: "none",
      padding: 10,
      borderRight: "1px solid var(--hairline)",
      background: "var(--surface-window)"
    }
  }, /*#__PURE__*/React.createElement(window.LayersPanel, {
    doc: doc,
    selected: selected,
    onSelect: setSelected
  })), /*#__PURE__*/React.createElement(window.Canvas, {
    doc: doc,
    selected: selected,
    onSelect: setSelected,
    zoom: zoom
  }), panels.right && /*#__PURE__*/React.createElement("div", {
    className: "glass-medium",
    style: {
      width: "var(--dock-right-width)",
      flex: "none",
      borderLeft: "1px solid var(--hairline)",
      overflow: "auto",
      borderRadius: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      height: "var(--panel-header-height)",
      padding: "0 12px",
      borderBottom: "1px solid var(--hairline)",
      position: "sticky",
      top: 0,
      background: "var(--glass-tint-medium)",
      backdropFilter: "blur(30px)",
      WebkitBackdropFilter: "blur(30px)",
      zIndex: 2
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph-fill ph-sliders-horizontal",
    style: {
      fontSize: 15,
      color: "var(--text-accent)"
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "exp-panel-title",
    style: {
      color: "var(--text-accent)",
      flex: 1
    }
  }, "Properties"), /*#__PURE__*/React.createElement("i", {
    className: "ph ph-caret-down",
    style: {
      fontSize: 13,
      color: "var(--text-tertiary)"
    }
  })), /*#__PURE__*/React.createElement(window.Inspector, {
    doc: doc,
    selected: selected,
    update: update
  }))));
}
window.EditorShell = EditorShell;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/EditorShell.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/Inspector.jsx
try { (() => {
// Inspector — the right Properties panel. Renders the right body per selection:
// a shape (full controls), an artboard (name/size/bg/layout grids), or nothing.
// Composes the DS field primitives.
const NS = window.EXPDesignDesignSystem_fb82b2;
function Row({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "0 var(--panel-pad-h)",
      ...style
    }
  }, children);
}
function AlignGrid() {
  const {
    SegmentedControl,
    IconButton
  } = NS;
  const [to, setTo] = React.useState("selection");
  const aligns = ["align-left", "align-center-horizontal", "align-right", "align-top", "align-center-vertical", "align-bottom"];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "10px var(--panel-pad-h)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "exp-section-title",
    style: {
      marginBottom: 8
    }
  }, "Align"), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: 0,
      marginBottom: 10,
      gap: 10
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "To"), /*#__PURE__*/React.createElement(SegmentedControl, {
    options: [{
      value: "selection",
      label: "Selection"
    }, {
      value: "artboard",
      label: "Artboard"
    }],
    value: to,
    onChange: setTo
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 2
    }
  }, aligns.slice(0, 3).map(a => /*#__PURE__*/React.createElement(AlignBtn, {
    key: a,
    icon: a
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 2
    }
  }, aligns.slice(3).map(a => /*#__PURE__*/React.createElement(AlignBtn, {
    key: a,
    icon: a
  })))), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: 0,
      marginTop: 12,
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "Distribute"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 6
    }
  }, /*#__PURE__*/React.createElement(AlignBtn, {
    icon: "rows"
  }), /*#__PURE__*/React.createElement(AlignBtn, {
    icon: "columns"
  }))));
}
function AlignBtn({
  icon
}) {
  const [h, setH] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", {
    onMouseEnter: () => setH(true),
    onMouseLeave: () => setH(false),
    style: {
      width: 38,
      height: 32,
      borderRadius: 6,
      border: "1px solid var(--border-soft)",
      background: h ? "var(--row-hover)" : "var(--surface-card)",
      cursor: "pointer",
      color: "var(--text-secondary)",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `ph ph-${icon}`,
    style: {
      fontSize: 15
    }
  }));
}
function ShapeInspector({
  layer,
  doc,
  update
}) {
  const {
    TextField,
    NumericField,
    Select,
    ColorWell,
    Divider,
    SectionHeader
  } = NS;
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "12px var(--panel-pad-h) 8px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "exp-section-title",
    style: {
      marginBottom: 6
    }
  }, "Layer"), /*#__PURE__*/React.createElement(TextField, {
    value: layer.name,
    weight: "medium",
    onChange: v => update({
      name: v
    })
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 8
    }
  }, /*#__PURE__*/React.createElement(NumericField, {
    label: "X",
    value: layer.X,
    onChange: v => update({
      X: v
    })
  }), /*#__PURE__*/React.createElement(NumericField, {
    label: "Y",
    value: layer.Y,
    onChange: v => update({
      Y: v
    })
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 8
    }
  }, /*#__PURE__*/React.createElement(NumericField, {
    label: "W",
    value: layer.W,
    onChange: v => update({
      W: v
    })
  }), /*#__PURE__*/React.createElement(NumericField, {
    label: "H",
    value: layer.H,
    onChange: v => update({
      H: v
    })
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 8,
      justifyContent: "space-between"
    }
  }, /*#__PURE__*/React.createElement(NumericField, {
    label: "R",
    value: layer.rot,
    unit: "\xB0",
    width: 64,
    onChange: v => update({
      rot: v
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "Opacity"), /*#__PURE__*/React.createElement(NumericField, {
    label: "",
    value: layer.opacity,
    unit: "%",
    min: 0,
    max: 100,
    width: 52,
    onChange: v => update({
      opacity: v
    })
  }))), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 10,
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "Blend"), /*#__PURE__*/React.createElement(Select, {
    options: doc.blendModes,
    value: layer.blend,
    onChange: v => update({
      blend: v
    }),
    width: 150
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: "12px var(--panel-pad-h)"
    }
  }, /*#__PURE__*/React.createElement(ColorWell, {
    label: "Fill",
    color: layer.fill,
    style: {
      flex: 1
    }
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "10px var(--panel-pad-h) 4px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "exp-section-title",
    style: {
      marginBottom: 8
    }
  }, "Stroke"), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: 0,
      marginBottom: 8
    }
  }, /*#__PURE__*/React.createElement(ColorWell, {
    label: "Color",
    color: layer.stroke,
    style: {
      flex: 1
    }
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-tertiary)",
      flex: 1
    }
  }, "Width"), /*#__PURE__*/React.createElement(NumericField, {
    label: "",
    value: layer.strokeW,
    width: 56,
    onChange: v => update({
      strokeW: v
    })
  }))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(AlignGrid, null), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Effects",
    action: "plus"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "0 var(--panel-pad-h) 14px",
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "No effects"));
}
function ArtboardInspector({
  ab
}) {
  const {
    TextField,
    NumericField,
    ColorWell,
    Divider,
    SectionHeader
  } = NS;
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "12px var(--panel-pad-h) 8px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "exp-section-title",
    style: {
      marginBottom: 6
    }
  }, "Artboard"), /*#__PURE__*/React.createElement(TextField, {
    value: ab.name,
    weight: "medium",
    onChange: () => {}
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 8
    }
  }, /*#__PURE__*/React.createElement(NumericField, {
    label: "X",
    value: ab.x,
    onChange: () => {}
  }), /*#__PURE__*/React.createElement(NumericField, {
    label: "Y",
    value: ab.y,
    onChange: () => {}
  })), /*#__PURE__*/React.createElement(Row, {
    style: {
      marginBottom: 10
    }
  }, /*#__PURE__*/React.createElement(NumericField, {
    label: "W",
    value: ab.w,
    onChange: () => {}
  }), /*#__PURE__*/React.createElement(NumericField, {
    label: "H",
    value: ab.h,
    onChange: () => {}
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    style: {
      padding: "12px var(--panel-pad-h)"
    }
  }, /*#__PURE__*/React.createElement(ColorWell, {
    label: "Background",
    color: ab.bg,
    style: {
      flex: 1
    }
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Layout Grids",
    action: "plus"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "0 var(--panel-pad-h) 14px",
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "No layout grids"));
}
function Inspector({
  doc,
  selected,
  update
}) {
  const layer = doc.layers.find(l => l.id === selected && l.X != null);
  return /*#__PURE__*/React.createElement("div", null, layer ? /*#__PURE__*/React.createElement(ShapeInspector, {
    layer: layer,
    doc: doc,
    update: update
  }) : selected === "ab" || selected == null ? /*#__PURE__*/React.createElement(ArtboardInspector, {
    ab: doc.artboards[0]
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "16px var(--panel-pad-h)",
      fontSize: 12,
      color: "var(--text-tertiary)"
    }
  }, "No selection"));
}
window.Inspector = Inspector;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/Inspector.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/LayersPanel.jsx
try { (() => {
// LayersPanel — the left dock: a Layers panel (tree) over a Components panel,
// the app's default left arrangement. Built from DS Panel + LayerRow + Badge.
const NS = window.EXPDesignDesignSystem_fb82b2;
function LayersPanel({
  doc,
  selected,
  onSelect
}) {
  const {
    Panel,
    LayerRow,
    Badge,
    IconButton
  } = NS;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 10,
      height: "100%"
    }
  }, /*#__PURE__*/React.createElement(Panel, {
    title: "Layers",
    icon: "stack-simple",
    accentTitle: true,
    style: {
      flex: 1,
      minHeight: 0
    },
    actions: /*#__PURE__*/React.createElement(IconButton, {
      icon: "dots-three",
      size: "sm",
      title: "Layer options"
    })
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "4px 0"
    }
  }, doc.layers.map(l => /*#__PURE__*/React.createElement(LayerRow, {
    key: l.id,
    name: l.name,
    kind: l.kind,
    depth: l.depth,
    expandable: l.expandable,
    expanded: l.expanded,
    hidden: l.hidden,
    locked: l.locked,
    selected: selected === l.id,
    onSelect: () => onSelect(l.id)
  })))), /*#__PURE__*/React.createElement(Panel, {
    title: "Components",
    icon: "squares-four",
    style: {
      flex: "none",
      height: 132
    },
    detachable: true,
    actions: /*#__PURE__*/React.createElement("i", {
      className: "ph ph-caret-down",
      style: {
        fontSize: 13,
        color: "var(--text-tertiary)"
      }
    })
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 10,
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, [["Some component name", "290 × 328 · 2 layers"], ["file-icons", "12 × 11 · 8 layers"]].map(([n, m]) => /*#__PURE__*/React.createElement("div", {
    key: n,
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 26,
      height: 26,
      borderRadius: 5,
      background: "var(--surface-card)",
      border: "1px solid var(--border-soft)",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      color: "var(--text-accent)",
      flex: "none"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph-fill ph-squares-four",
    style: {
      fontSize: 14
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      lineHeight: 1.3,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--text-primary)",
      fontWeight: "var(--w-light)",
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, n), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 10,
      color: "var(--text-tertiary)",
      fontFamily: "var(--font-mono)"
    }
  }, m)))))));
}
window.LayersPanel = LayersPanel;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/LayersPanel.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/TopBar.jsx
try { (() => {
// TopBar — the macOS title bar: traffic lights · document name · centered
// new-artboard control · right system cluster (zoom, panel toggles, workspace,
// appearance). Cosmetic recreation of MainWindow's toolbar.
const NS = window.EXPDesignDesignSystem_fb82b2;
function TrafficLights() {
  const dots = [["#ff5f57", "#e0443e"], ["#febc2e", "#d89e24"], ["#28c840", "#1aab29"]];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8,
      alignItems: "center"
    }
  }, dots.map(([a, b], i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      width: 12,
      height: 12,
      borderRadius: 999,
      background: a,
      boxShadow: `inset 0 0 0 0.5px ${b}`
    }
  })));
}
function TopBar({
  doc,
  zoom,
  setZoom,
  appearance,
  setAppearance,
  panels,
  setPanels
}) {
  const {
    IconButton,
    Tooltip
  } = NS;
  return /*#__PURE__*/React.createElement("div", {
    className: "glass-thin",
    style: {
      height: "var(--titlebar-height)",
      display: "flex",
      alignItems: "center",
      padding: "0 16px",
      gap: 16,
      borderBottom: "1px solid var(--hairline)",
      flex: "none",
      position: "relative",
      zIndex: 5
    }
  }, /*#__PURE__*/React.createElement(TrafficLights, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      lineHeight: 1.15,
      marginLeft: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 13,
      fontWeight: "var(--w-medium)",
      color: "var(--text-primary)"
    }
  }, doc.docName, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--text-tertiary)",
      fontWeight: "var(--w-light)"
    }
  }, ".design")), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 10,
      color: "var(--text-tertiary)",
      fontWeight: "var(--w-light)"
    }
  }, "Edited")), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: "50%",
      transform: "translateX(-50%)",
      display: "flex",
      alignItems: "center",
      height: 28,
      borderRadius: 8,
      background: "var(--surface-field)",
      border: "1px solid var(--border-glass)",
      boxShadow: "var(--glass-inner-hi)"
    }
  }, /*#__PURE__*/React.createElement("button", {
    style: iconTrigger
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph-bold ph-plus",
    style: {
      fontSize: 14
    }
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      height: 16,
      background: "var(--hairline)"
    }
  }), /*#__PURE__*/React.createElement("button", {
    style: iconTrigger
  }, /*#__PURE__*/React.createElement("i", {
    className: "ph-bold ph-caret-down",
    style: {
      fontSize: 11
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 4
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: "magnifying-glass-minus",
    title: "Zoom out",
    onClick: () => setZoom(Math.max(5, zoom - 10))
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 34,
      textAlign: "center",
      fontSize: 12,
      fontVariantNumeric: "tabular-nums",
      color: "var(--text-primary)"
    }
  }, zoom), /*#__PURE__*/React.createElement(IconButton, {
    icon: "magnifying-glass-plus",
    title: "Zoom in",
    onClick: () => setZoom(Math.min(400, zoom + 10))
  }), /*#__PURE__*/React.createElement(IconButton, {
    icon: "arrows-out-simple",
    title: "Zoom presets"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      height: 16,
      background: "var(--hairline)",
      margin: "0 6px"
    }
  }), /*#__PURE__*/React.createElement(IconButton, {
    icon: "sidebar-simple",
    active: panels.left,
    title: "Left panel",
    onClick: () => setPanels({
      ...panels,
      left: !panels.left
    })
  }), /*#__PURE__*/React.createElement(IconButton, {
    icon: "sidebar-simple",
    active: panels.right,
    title: "Right panel",
    style: {
      transform: "scaleX(-1)"
    },
    onClick: () => setPanels({
      ...panels,
      right: !panels.right
    })
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      height: 16,
      background: "var(--hairline)",
      margin: "0 6px"
    }
  }), /*#__PURE__*/React.createElement(Tooltip, {
    label: appearance === "exp-dark" ? "Light appearance" : "Dark appearance",
    side: "bottom"
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: appearance === "exp-dark" ? "sun" : "moon",
    onClick: () => setAppearance(appearance === "exp-dark" ? "exp-light" : "exp-dark"),
    title: "Appearance"
  }))));
}
const iconTrigger = {
  width: 30,
  height: 28,
  display: "inline-flex",
  alignItems: "center",
  justifyContent: "center",
  background: "none",
  border: "none",
  cursor: "pointer",
  color: "var(--text-primary)"
};
window.TopBar = TopBar;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/TopBar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/exp-editor/data.js
try { (() => {
// Sample document model for the EXP [design] editor UI kit. Mirrors the app's
// Node/Artboard shape closely enough for a cosmetic recreation.
window.EXP_DOC = {
  docName: "awesome document #5",
  zoom: 94,
  artboards: [{
    id: "ab1",
    name: "Artboard 1",
    x: 0,
    y: 0,
    w: 393,
    h: 852,
    bg: "#ffffff"
  }],
  // Flat list with depth for the layers tree.
  layers: [{
    id: "ab",
    name: "Artboard name",
    kind: "artboard",
    depth: 0,
    expandable: true,
    expanded: true
  }, {
    id: "t1",
    name: "a text layer.",
    kind: "text",
    depth: 1,
    X: 32,
    Y: 64,
    W: 240,
    H: 38,
    rot: 0,
    opacity: 100,
    blend: "Normal",
    fill: "#1a1a1c",
    stroke: "#000000",
    strokeW: 0
  }, {
    id: "c1",
    name: "Some component name",
    kind: "component",
    depth: 1,
    expandable: true,
    X: 32,
    Y: 140,
    W: 290,
    H: 96,
    rot: 0,
    opacity: 100,
    blend: "Normal",
    fill: "#2b6fdb",
    stroke: "#000000",
    strokeW: 0
  }, {
    id: "i1",
    name: "image layer",
    kind: "image",
    depth: 1,
    X: 32,
    Y: 260,
    W: 290,
    H: 180,
    rot: 0,
    opacity: 100,
    blend: "Normal",
    fill: "#3a3a3e",
    stroke: "#000000",
    strokeW: 0
  }, {
    id: "g1",
    name: "another group",
    kind: "group",
    depth: 1,
    expandable: true,
    locked: true
  }, {
    id: "g2",
    name: "expanded group",
    kind: "group",
    depth: 1,
    expandable: true,
    expanded: true
  }, {
    id: "i2",
    name: "image layer",
    kind: "image",
    depth: 2,
    X: 48,
    Y: 470,
    W: 200,
    H: 130,
    rot: 0,
    opacity: 100,
    blend: "Normal",
    fill: "#4a4a50",
    stroke: "#000000",
    strokeW: 0
  }, {
    id: "p1",
    name: "another long layer name that…",
    kind: "path",
    depth: 2,
    hidden: true,
    X: 60,
    Y: 620,
    W: 120,
    H: 80,
    rot: 12,
    opacity: 80,
    blend: "Multiply",
    fill: "#4ce62e",
    stroke: "#000000",
    strokeW: 0
  }, {
    id: "e1",
    name: "some shape. huzzah",
    kind: "ellipse",
    depth: 1,
    X: 120,
    Y: 700,
    W: 100,
    H: 100,
    rot: 0,
    opacity: 100,
    blend: "Normal",
    fill: "#d9d9de",
    stroke: "#000000",
    strokeW: 0
  }],
  blendModes: ["Normal", "Multiply", "Screen", "Overlay", "Soft Light", "Hard Light", "Color Dodge", "Color Burn", "Difference", "Exclusion", "Hue", "Saturation", "Color", "Luminosity"]
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/exp-editor/data.js", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.Slider = __ds_scope.Slider;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Tooltip = __ds_scope.Tooltip;

__ds_ns.ColorWell = __ds_scope.ColorWell;

__ds_ns.NumericField = __ds_scope.NumericField;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.LayerRow = __ds_scope.LayerRow;

__ds_ns.Panel = __ds_scope.Panel;

__ds_ns.SectionHeader = __ds_scope.SectionHeader;

__ds_ns.ToolStrip = __ds_scope.ToolStrip;

})();
