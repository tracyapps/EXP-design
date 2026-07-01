import * as React from "react";
export type LayerKind =
  | "text" | "image" | "component" | "instance" | "group"
  | "rectangle" | "ellipse" | "line" | "path" | "polygon" | "artboard";
export interface LayerRowProps {
  name: string;
  kind?: LayerKind;
  depth?: number;
  selected?: boolean;
  hidden?: boolean;
  locked?: boolean;
  expandable?: boolean;
  expanded?: boolean;
  onToggle?: () => void;
  onSelect?: () => void;
  onToggleHidden?: () => void;
  onToggleLock?: () => void;
  style?: React.CSSProperties;
}
/** One Layers-panel row: chevron · eye · type glyph · name · lock. */
export function LayerRow(props: LayerRowProps): JSX.Element;
