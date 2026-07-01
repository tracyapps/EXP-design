import * as React from "react";
export interface SectionHeaderProps {
  title: string;
  /** Phosphor icon name for a trailing action (e.g. "plus"). */
  action?: string;
  onAction?: () => void;
  style?: React.CSSProperties;
}
/** Inspector section label in ultralight type with an optional trailing action. */
export function SectionHeader(props: SectionHeaderProps): JSX.Element;
