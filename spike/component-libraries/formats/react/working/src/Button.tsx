import type { ButtonHTMLAttributes, ReactNode } from 'react';

export type ButtonProps = {
  /** Visual emphasis. */
  appearance?: 'primary' | 'secondary' | 'ghost';
  /** Size. */
  size?: 's' | 'm' | 'l';
  /** Disables the button. */
  disabled?: boolean;
  /** The button's label. */
  children: ReactNode;
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'disabled'>;

/** Simple action button. Styles: styles/button.css */
export function Button({ appearance = 'primary', size = 'm', disabled = false, children, className, ...rest }: ButtonProps) {
  const classes = ['exp-button', `exp-button--${appearance}`, `exp-button--${size}`, className].filter(Boolean).join(' ');
  return (
    <button type="button" {...rest} className={classes} disabled={disabled}>
      {children}
    </button>
  );
}
