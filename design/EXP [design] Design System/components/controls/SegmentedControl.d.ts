import * as React from "react";

export interface SegOption { value: string; label?: string; icon?: string; }
export interface SegmentedControlProps {
  options: SegOption[] | string[];
  value: string;
  onChange?: (value: string) => void;
  size?: "sm" | "md";
  fill?: "accent" | "neutral";
  style?: React.CSSProperties;
}
/** Pill toggle — Selection/Artboard, row/column, Gap/Space-Between. */
export function SegmentedControl(props: SegmentedControlProps): JSX.Element;
