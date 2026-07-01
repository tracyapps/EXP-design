import * as React from "react";
export interface SelectOption { value: string; label?: string; }
export interface SelectProps {
  options: SelectOption[] | string[];
  value: string;
  onChange?: (value: string) => void;
  width?: number | string;
  disabled?: boolean;
  style?: React.CSSProperties;
}
/** Dropdown select with a glass popover list (Blend mode, units). */
export function Select(props: SelectProps): JSX.Element;
