import * as React from "react";
export interface ToolDef { id: string; icon: string; label: string; }
export interface ToolStripProps {
  groups?: ToolDef[][];
  active?: string;
  onSelect?: (id: string) => void;
  style?: React.CSSProperties;
}
/**
 * Fixed left tools rail (thin glass), tools grouped by purpose.
 * @startingPoint section="Structure" subtitle="Left tools rail" viewport="44x420"
 */
export function ToolStrip(props: ToolStripProps): JSX.Element;
