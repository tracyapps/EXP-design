import * as React from "react";

export interface CheckboxProps {
  checked?: boolean;
  onChange?: (next: boolean) => void;
  label?: string;
  disabled?: boolean;
  style?: React.CSSProperties;
}
/** Square checkbox (Show grid, Snap to grid). Optional trailing label. */
export function Checkbox(props: CheckboxProps): JSX.Element;
