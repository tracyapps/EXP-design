import * as React from "react";

export interface SwitchProps {
  checked?: boolean;
  onChange?: (next: boolean) => void;
  disabled?: boolean;
  size?: "mini" | "small";
  style?: React.CSSProperties;
}
/** macOS toggle switch; `mini` matches the inspector default. */
export function Switch(props: SwitchProps): JSX.Element;
