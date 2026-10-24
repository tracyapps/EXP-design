import { LitElement, css, html } from 'lit';
import { stylesheet } from './styles.js';

/**
 * A button. The label is the default slot.
 *
 * @summary Simple action button.
 * @slot - The button's label.
 * @csspart control - The native <button>.
 * @cssprop --exp-button-radius - Corner radius.
 * @cssprop --exp-button-padding-inline - Horizontal padding.
 * @fires lit-press - When the button is activated (not while disabled).
 */
export class LitButton extends LitElement {
  static override shadowRootOptions = { ...LitElement.shadowRootOptions, delegatesFocus: true };
  static override styles = css`:host { display: inline-block; } :host([hidden]) { display: none; }`;
  static override properties = {
    appearance: { type: String, reflect: true },
    size: { type: String, reflect: true },
    disabled: { type: Boolean, reflect: true },
  };

  /** Visual emphasis. */
  appearance: 'primary' | 'secondary' | 'ghost' = 'primary';
  /** Size. */
  size: 's' | 'm' | 'l' = 'm';
  /** Disables the button. */
  disabled = false;

  override render() {
    return html`${stylesheet('button.css')}
      <button type="button" part="control" ?disabled=${this.disabled}
        class="exp-button exp-button--${this.appearance} exp-button--${this.size}"
        @click=${this.press}><slot></slot></button>`;
  }

  private press() {
    if (!this.disabled) this.dispatchEvent(new CustomEvent('lit-press', { bubbles: true, composed: true }));
  }
}

customElements.define('lit-button', LitButton);

declare global {
  interface HTMLElementTagNameMap { 'lit-button': LitButton; }
}
