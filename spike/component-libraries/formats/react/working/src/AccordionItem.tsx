import { createElement, useId, type ReactNode } from 'react';

export type AccordionItemProps = {
  /** The section title. */
  title: string;
  /** Whether the panel is shown. */
  open: boolean;
  /** Heading level (set by Accordion). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
  onToggle: () => void;
  children: ReactNode;
};

/**
 * One accordion section (child of Accordion). WAI-ARIA APG accordion pattern:
 * a button inside a heading with aria-expanded/aria-controls, and a region
 * panel labelled by that button.
 */
export function AccordionItem({ title, open, headingLevel = 3, onToggle, children }: AccordionItemProps) {
  const id = useId();
  const triggerId = `${id}-trigger`;
  const panelId = `${id}-panel`;
  return (
    <div className="exp-accordion__item">
      {createElement(
        `h${headingLevel}`,
        { className: 'exp-accordion__heading' },
        <button type="button" className="exp-accordion__trigger" id={triggerId}
          aria-expanded={open} aria-controls={panelId} onClick={onToggle}>
          <span>{title}</span>
          <span className="exp-accordion__icon" aria-hidden="true" />
        </button>,
      )}
      <div className="exp-accordion__panel" id={panelId} role="region" aria-labelledby={triggerId} hidden={!open}>
        {children}
      </div>
    </div>
  );
}
