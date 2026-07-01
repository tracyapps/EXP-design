import * as React from "react";

export interface IconProps extends React.HTMLAttributes<HTMLElement> {
  /** Phosphor icon name (without the `ph-` prefix), e.g. "cursor", "lock-simple". */
  name: string;
  /** Phosphor weight. Use "fill" for active/selected glyphs, "regular" idle. */
  weight?: "thin" | "light" | "regular" | "bold" | "fill" | "duotone";
  size?: number;
  color?: string;
}
/** Phosphor-Icons wrapper standing in for the app's native SF Symbols. */
export function Icon(props: IconProps): JSX.Element;
