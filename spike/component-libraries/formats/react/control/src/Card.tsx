import { createElement } from 'react';
import { Button, type ButtonProps } from './Button';

export type CardAction = Pick<ButtonProps, 'appearance' | 'size'> & { label: string; onClick?: () => void };

export type CardProps = {
  /** Short label above the title. */
  eyebrow?: string;
  /** The card title. */
  title: string;
  /** Body text. */
  body?: string;
  /** Elevated or outlined. */
  tone?: 'raised' | 'plain';
  /** Heading level for the title (2–6). */
  headingLevel?: 2 | 3 | 4 | 5 | 6;
  /** Buttons rendered in the actions row (child Button components). */
  actions?: CardAction[];
};

/** Composite card: composes Button children. Styles: styles/card.css */
export function Card({ eyebrow, title, body, tone = 'raised', headingLevel = 3, actions = [] }: CardProps) {
  return (
    <article className={`exp-card exp-card--${tone}`}>
      {eyebrow && <p className="exp-card__eyebrow">{eyebrow}</p>}
      {createElement(`h${headingLevel}`, { className: 'exp-card__title' }, title)}
      {body && <p className="exp-card__body">{body}</p>}
      {actions.length > 0 && (
        <div className="exp-card__actions">
          {actions.map(({ label, ...action }) => (
            <Button key={label} {...action}>{label}</Button>
          ))}
        </div>
      )}
    </article>
  );
}
