import * as React from "react";
export interface TextFieldProps {
  value: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  weight?: "ultralight" | "light" | "regular" | "medium";
  align?: "left" | "center" | "right";
  monospace?: boolean;
  disabled?: boolean;
  style?: React.CSSProperties;
}
/**
 * Rounded-border single-line text input (layer / artboard name).
 * @startingPoint section="Inputs" subtitle="Text + numeric fields" viewport="700x150"
 */
export function TextField(props: TextFieldProps): JSX.Element;
