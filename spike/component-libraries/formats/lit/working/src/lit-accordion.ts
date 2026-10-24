import { LitElement, css, html } from 'lit';
import { stylesheet, uid } from './styles.js';

/**
 * One accordion section. Use inside lit-accordion. WAI-ARIA APG accordion
 * pattern: a button inside a heading with aria-expanded/aria-controls, and a
 * region panel labelled by that button.
 *
 * @summary Accordion section (child of lit-accordion).
 * @slot - Panel content.
 * @csspart trigger - The header button.
 * @csspart panel - The content region.
 * @fires lit-toggle - When the user opens or closes the section. detail: { open }
 */
export class LitAccordionItem extends LitElement {
  static override styles = css`:host { display: block; }`;
  static override properties = {
    heading: { type: String },
    open: { type: Boolean, reflect: true },
    headingLevel: { type: Number, attribute: 'heading-level' },
  };

  /** The section title. */
  heading = '';
  /** Whether the panel is shown. */
  open = false;
  /** Set by the parent lit-accordion. */
  headingLevel = 3;
  private readonly uidBase = uid('lit-accordion');

  override render() {
    return html`${stylesheet('accordion.css')}
      <div class="exp-accordion__item">
        <div class="exp-accordion__heading" role="heading" aria-level=${this.headingLevel}>
          <button type="button" class="exp-accordion__trigger" part="trigger"
            id="${this.uidBase}-trigger" aria-controls="${this.uidBase}-panel"
            aria-expanded=${String(this.open)} @click=${this.toggle}>
            <span>${this.heading}</span><span class="exp-accordion__icon" aria-hidden="true"></span>
          </button>
        </div>
        <div class="exp-accordion__panel" part="panel" id="${this.uidBase}-panel" role="region"
          aria-labelledby="${this.uidBase}-trigger" ?hidden=${!this.open}><slot></slot></div>
      </div>`;
  }

  private toggle() {
    this.open = !this.open;
    this.dispatchEvent(new CustomEvent('lit-toggle', { bubbles: true, composed: true, detail: { open: this.open } }));
  }
}

/**
 * A set of collapsible sections made of lit-accordion-item children.
 *
 * @summary Accordion container.
 * @slot - lit-accordion-item elements.
 * @cssprop --exp-accordion-gap - Space between sections.
 */
export class LitAccordion extends LitElement {
  static override styles = css`:host { display: block; }`;
  static override properties = {
    allowMultiple: { type: Boolean, attribute: 'allow-multiple' },
    headingLevel: { type: Number, attribute: 'heading-level' },
  };

  /** Allow more than one open section. */
  allowMultiple = false;
  /** Heading level passed to every item. */
  headingLevel = 3;

  constructor() {
    super();
    this.addEventListener('lit-toggle', (event) => {
      const detail = (event as CustomEvent<{ open: boolean }>).detail;
      if (this.allowMultiple || !detail.open) return;
      for (const item of this.items) if (item !== event.target) item.open = false;
    });
  }

  private get items() { return [...this.querySelectorAll<LitAccordionItem>(':scope > lit-accordion-item')]; }

  override updated() { this.syncLevels(); }

  override render() {
    return html`${stylesheet('accordion.css')}<div class="exp-accordion"><slot @slotchange=${this.syncLevels}></slot></div>`;
  }

  private syncLevels() {
    for (const item of this.items) item.headingLevel = this.headingLevel;
  }
}

customElements.define('lit-accordion-item', LitAccordionItem);
customElements.define('lit-accordion', LitAccordion);

declare global {
  interface HTMLElementTagNameMap {
    'lit-accordion': LitAccordion;
    'lit-accordion-item': LitAccordionItem;
  }
}
