import * as React from "react";

export interface ButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "style"> {
  variant?: "primary" | "secondary" | "ghost" | "destructive";
  size?: "sm" | "md" | "lg";
  /** Leading Phosphor icon name. */
  icon?: string;
  iconWeight?: string;
  disabled?: boolean;
  style?: React.CSSProperties;
}

/**
 * Primary action button — Liquid Glass with accent tint.
 * @dsCard
 * @startingPoint section="Controls" subtitle="Glass action button, 4 variants" viewport="700x150"
 */
export function Button(props: ButtonProps): JSX.Element;
