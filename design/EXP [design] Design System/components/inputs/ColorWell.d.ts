import * as React from "react";
export interface ColorWellProps {
  /** Any CSS color or gradient string. */
  color?: string;
  label?: string;
  onClick?: () => void;
  size?: "sm" | "md";
  style?: React.CSSProperties;
}
/** Fill / Stroke colour swatch over a checkerboard; opens a host colour popover. */
export function ColorWell(props: ColorWellProps): JSX.Element;
