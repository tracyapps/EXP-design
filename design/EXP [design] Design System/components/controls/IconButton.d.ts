import * as React from "react";

export interface IconButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "style"> {
  /** Phosphor icon name. */
  icon: string;
  weight?: string;
  active?: boolean;
  size?: "sm" | "md" | "lg";
  disabled?: boolean;
  title?: string;
  style?: React.CSSProperties;
}
/** Borderless square glyph button for toolbars, rows, and the tools strip. */
export function IconButton(props: IconButtonProps): JSX.Element;
