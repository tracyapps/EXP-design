import React from "react";
import { IconButton } from "../controls/IconButton.jsx";

/**
 * ToolStrip — the fixed vertical tools rail pinned to the window's left edge.
 * Thin glass, grouped tools separated by hairlines, active tool accent-tinted.
 * Default tools mirror the app's Tool enum.
 */
const DEFAULT_GROUPS = [
  [{ id: "select", icon: "cursor", label: "Select" }, { id: "node", icon: "bezier-curve", label: "Edit Points" }],
  [{ id: "rectangle", icon: "square", label: "Rectangle" }, { id: "ellipse", icon: "circle", label: "Ellipse" },
   { id: "polygon", icon: "triangle", label: "Polygon" }, { id: "line", icon: "line-segment", label: "Line" }],
  [{ id: "pen", icon: "pen-nib", label: "Pen" }, { id: "text", icon: "text-t", label: "Text" }],
];

export function ToolStrip({ groups = DEFAULT_GROUPS, active = "select", onSelect, style = {} }) {
  return (
    <div className="glass-thin" style={{
      width: "var(--tools-strip-width)", display: "flex", flexDirection: "column",
      alignItems: "center", gap: 4, padding: "8px 0", borderRight: "1px solid var(--hairline)",
      ...style,
    }}>
      {groups.map((group, gi) => (
        <React.Fragment key={gi}>
          {gi > 0 && <span style={{ width: 22, height: 1, background: "var(--hairline)", margin: "4px 0" }} />}
          {group.map((t) => (
            <IconButton key={t.id} icon={t.icon} title={t.label} active={active === t.id} size="lg"
              onClick={() => onSelect && onSelect(t.id)} />
          ))}
        </React.Fragment>
      ))}
    </div>
  );
}
