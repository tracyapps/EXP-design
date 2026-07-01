import * as React from "react";
export interface DividerProps {
  vertical?: boolean;
  inset?: number;
  style?: React.CSSProperties;
}
/** Hairline separator. */
export function Divider(props: DividerProps): JSX.Element;
