import { styleLink, uid } from './shared.js';

/**
 * One accordion section. Use inside wc-accordion.
 * Follows the WAI-ARIA APG accordion pattern: a button inside a heading with
 * aria-expanded/aria-controls, and a region panel labelled by that button.
 *
 * @summary Accordion section (child of wc-accordion).
 * @tag wc-accordion-item
 *
 * @attr {string} heading - The section title.
 * @attr {boolean} open - Whether the panel is shown.
 * @attr {number} heading-level - Set by the parent wc-accordion. Default 3.
 *
 * @slot - Panel content.
 * @csspart trigger - The header button.
 * @csspart panel - The content region.
 * @fires wc-toggle - When the user opens or closes the section. detail: { open }
 */
export class WcAccordionItem extends HTMLElement {
  static observedAttributes = ['heading', 'open', 'heading-level'];

  constructor() {
    super();
    const root = this.attachShadow({ mode: 'open' });
    const id = uid('wc-accordion');
    const item = document.createElement('div');
    item.className = 'exp-accordion__item';
    item.innerHTML = `
      <div class="exp-accordion__heading" role="heading" aria-level="3">
        <button type="button" class="exp-accordion__trigger" part="trigger"
                id="${id}-trigger" aria-controls="${id}-panel" aria-expanded="false">
          <span class="label"></span><span class="exp-accordion__icon" aria-hidden="true"></span>
        </button>
      </div>
      <div class="exp-accordion__panel" part="panel" id="${id}-panel"
           role="region" aria-labelledby="${id}-trigger" hidden><slot></slot></div>`;
    const host = document.createElement('style');
    host.textContent = ':host { display: block; }';
    root.append(styleLink('accordion.css'), host, item);
    this.heading = item.querySelector('[role="heading"]');
    this.trigger = item.querySelector('button');
    this.panel = item.querySelector('[role="region"]');
    this.trigger.addEventListener('click', () => {
      this.open = !this.open;
      this.dispatchEvent(new CustomEvent('wc-toggle', { bubbles: true, composed: true, detail: { open: this.open } }));
    });
  }

  get open() { return this.hasAttribute('open'); }
  set open(value) { this.toggleAttribute('open', Boolean(value)); }

  connectedCallback() { this.render(); }
  attributeChangedCallback() { this.render(); }

  render() {
    this.trigger.querySelector('.label').textContent = this.getAttribute('heading') ?? '';
    this.trigger.setAttribute('aria-expanded', String(this.open));
    this.panel.hidden = !this.open;
    this.heading.setAttribute('aria-level', this.getAttribute('heading-level') ?? '3');
  }
}

/**
 * A set of collapsible sections made of wc-accordion-item children.
 *
 * @summary Accordion container.
 * @tag wc-accordion
 *
 * @attr {boolean} allow-multiple - Allow more than one open section.
 * @attr {number} heading-level - Heading level passed to every item. Default 3.
 *
 * @slot - wc-accordion-item elements.
 * @cssprop --exp-accordion-gap - Space between sections.
 */
export class WcAccordion extends HTMLElement {
  static observedAttributes = ['heading-level'];

  constructor() {
    super();
    const root = this.attachShadow({ mode: 'open' });
    const wrapper = document.createElement('div');
    wrapper.className = 'exp-accordion';
    wrapper.append(document.createElement('slot'));
    const host = document.createElement('style');
    host.textContent = ':host { display: block; }';
    root.append(styleLink('accordion.css'), host, wrapper);
    root.querySelector('slot').addEventListener('slotchange', () => this.syncLevels());
    this.addEventListener('wc-toggle', (event) => {
      if (this.hasAttribute('allow-multiple') || !event.detail.open) return;
      for (const item of this.items) if (item !== event.target) item.open = false;
    });
  }

  get items() { return [...this.querySelectorAll(':scope > wc-accordion-item')]; }
  connectedCallback() { this.syncLevels(); }
  attributeChangedCallback() { this.syncLevels(); }

  syncLevels() {
    const level = this.getAttribute('heading-level') ?? '3';
    for (const item of this.items) item.setAttribute('heading-level', level);
  }
}

customElements.define('wc-accordion-item', WcAccordionItem);
customElements.define('wc-accordion', WcAccordion);
