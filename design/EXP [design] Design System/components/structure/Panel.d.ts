import * as React from "react";
export interface PanelProps {
  title: string;
  /** Phosphor icon name for the header. */
  icon?: string;
  material?: "thin" | "medium" | "thick";
  /** Trailing header controls (e.g. a "…" menu IconButton). */
  actions?: React.ReactNode;
  detachable?: boolean;
  accentTitle?: boolean;
  children?: React.ReactNode;
  style?: React.CSSProperties;
  bodyStyle?: React.CSSProperties;
}
/**
 * Liquid-glass dock / floating panel shell with an uppercase title bar.
 * @startingPoint section="Structure" subtitle="Glass panel with header" viewport="320x420"
 */
export function Panel(props: PanelProps): JSX.Element;
