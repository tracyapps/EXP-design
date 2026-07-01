import * as React from "react";
export interface NumericFieldProps {
  /** Single-letter prefix (X / Y / W / H / R). */
  label?: string;
  value: number;
  onChange?: (value: number) => void;
  /** Trailing unit shown inside the field (°, %, px). */
  unit?: string;
  min?: number;
  max?: number;
  width?: number;
  disabled?: boolean;
  style?: React.CSSProperties;
}
/** Inspector numeric field — labelled, right-aligned, tabular digits. */
export function NumericField(props: NumericFieldProps): JSX.Element;
