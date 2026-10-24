import { styleLink } from './shared.js';

/**
 * A card that composes wc-button children in its actions row.
 *
 * @summary Composite card with actions.
 * @tag wc-card
 *
 * @attr {'raised' | 'plain'} tone - Elevated or outlined.
 * @attr {number} heading-level - Heading level for the title (2–6). Default 3.
 *
 * @slot eyebrow - Short label above the title.
 * @slot heading - The card title.
 * @slot - Body text.
 * @slot actions - wc-button elements.
 * @csspart base - The card container.
 * @cssprop --exp-card-padding - Inner padding.
 * @cssprop --exp-card-radius - Corner radius.
 */
export class WcCard extends HTMLElement {
  static observedAttributes = ['tone', 'heading-level'];

  constructor() {
    super();
    const root = this.attachShadow({ mode: 'open' });
    const host = document.createElement('style');
    host.textContent = ':host { display: block; }';
    this.base = document.createElement('article');
    this.base.part = 'base';
    this.base.innerHTML = `
      <p class="exp-card__eyebrow"><slot name="eyebrow"></slot></p>
      <div class="exp-card__title" role="heading"><slot name="heading"></slot></div>
      <p class="exp-card__body"><slot></slot></p>
      <div class="exp-card__actions"><slot name="actions"></slot></div>`;
    root.append(styleLink('card.css'), host, this.base);
    // Hide empty rows so they don't add gaps or empty paragraphs.
    for (const slot of this.base.querySelectorAll('slot')) {
      slot.addEventListener('slotchange', () => this.syncEmpty());
    }
  }

  get tone() { return this.getAttribute('tone') ?? 'raised'; }
  set tone(value) { this.setAttribute('tone', value); }
  get headingLevel() {
    const level = Number(this.getAttribute('heading-level') ?? 3);
    return Math.min(6, Math.max(2, Number.isFinite(level) ? level : 3));
  }

  connectedCallback() { this.render(); this.syncEmpty(); }
  attributeChangedCallback() { this.render(); }

  render() {
    this.base.className = `exp-card exp-card--${this.tone}`;
    this.base.querySelector('[role="heading"]').setAttribute('aria-level', String(this.headingLevel));
  }

  syncEmpty() {
    for (const slot of this.base.querySelectorAll('slot')) {
      slot.parentElement.hidden = slot.assignedNodes({ flatten: true })
        .every((node) => node.nodeType === Node.TEXT_NODE && !node.textContent.trim());
    }
  }
}

customElements.define('wc-card', WcCard);
