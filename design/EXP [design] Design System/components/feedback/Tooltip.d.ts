import * as React from "react";
export interface TooltipProps {
  label: string;
  /** Optional keyboard hint rendered as a kbd chip. */
  shortcut?: string;
  side?: "top" | "bottom" | "left" | "right";
  children?: React.ReactNode;
  style?: React.CSSProperties;
}
/** macOS help bubble (glass) with an optional shortcut chip. */
export function Tooltip(props: TooltipProps): JSX.Element;
