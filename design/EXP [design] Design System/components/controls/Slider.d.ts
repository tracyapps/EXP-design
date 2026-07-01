import * as React from "react";

export interface SliderProps {
  value: number;
  min?: number;
  max?: number;
  step?: number;
  onChange?: (value: number) => void;
  style?: React.CSSProperties;
}
/** Thin accent-filled value slider (zoom, gradient stops). */
export function Slider(props: SliderProps): JSX.Element;
