import { useState } from 'react';
import { AccordionItem } from './AccordionItem';

export type AccordionEntry = { title: string; content: string; open?: boolean };

export type AccordionProps = {
  /** Sections, rendered as AccordionItem children. */
  items: AccordionEntry[];
  /** Allow more than one open section. */
  allowMultiple?: boolean;
  /** Heading level for every section title (2–6). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
};

/** Accordion container. Styles: styles/accordion.css */
export function Accordion({ items, allowMultiple = false, headingLevel = 3 }: AccordionProps) {
  const [open, setOpen] = useState<boolean[]>(() => items.map((item) => Boolean(item.open)));
  const toggle = (index: number) =>
    setOpen((current) => current.map((value, i) => (i === index ? !value : allowMultiple ? value : false)));
  return (
    <div className="exp-accordion">
      {items.map((item, index) => (
        <AccordionItem key={item.title} title={item.title} open={open[index]}
          headingLevel={headingLevel} onToggle={() => toggle(index)}>
          <p>{item.content}</p>
        </AccordionItem>
      ))}
    </div>
  );
}
