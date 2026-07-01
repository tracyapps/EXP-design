import * as React from "react";
export interface BadgeProps {
  children?: React.ReactNode;
  tone?: "neutral" | "accent" | "brand" | "red";
  dot?: boolean;
  dotColor?: string;
  style?: React.CSSProperties;
}
/** Small status/count pill; `tone="brand"` gives the lime "live" dot. */
export function Badge(props: BadgeProps): JSX.Element;
