import { styleLink } from './shared.js';

/**
 * A button. The label is the default slot.
 *
 * @summary Simple action button.
 * @tag wc-button
 *
 * @attr {'primary' | 'secondary' | 'ghost'} appearance - Visual emphasis.
 * @attr {'s' | 'm' | 'l'} size - Size.
 * @attr {boolean} disabled - Disables the button.
 *
 * @slot - The button's label.
 * @csspart control - The native <button>.
 * @cssprop --exp-button-radius - Corner radius.
 * @cssprop --exp-button-padding-inline - Horizontal padding.
 * @fires wc-press - When the button is activated (not while disabled).
 */
export class WcButton extends HTMLElement {
  static observedAttributes = ['appearance', 'size', 'disabled'];

  constructor() {
    super();
    const root = this.attachShadow({ mode: 'open', delegatesFocus: true });
    const host = document.createElement('style');
    host.textContent = ':host { display: inline-block; } :host([hidden]) { display: none; }';
    this.control = document.createElement('button');
    this.control.type = 'button';
    this.control.part = 'control';
    this.control.append(document.createElement('slot'));
    this.control.addEventListener('click', () => {
      if (!this.disabled) this.dispatchEvent(new CustomEvent('wc-press', { bubbles: true, composed: true }));
    });
    root.append(styleLink('button.css'), host, this.control);
  }

  get appearance() { return this.getAttribute('appearance') ?? 'primary'; }
  set appearance(value) { this.setAttribute('appearance', value); }
  get size() { return this.getAttribute('size') ?? 'm'; }
  set size(value) { this.setAttribute('size', value); }
  get disabled() { return this.hasAttribute('disabled'); }
  set disabled(value) { this.toggleAttribute('disabled', Boolean(value)); }

  connectedCallback() { this.render(); }
  attributeChangedCallback() { this.render(); }

  render() {
    this.control.className = `exp-button exp-button--${this.appearance} exp-button--${this.size}`;
    this.control.disabled = this.disabled;
  }
}

customElements.define('wc-button', WcButton);
