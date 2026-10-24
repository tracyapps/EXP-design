import { LitElement, css, html } from 'lit';
import { stylesheet } from './styles.js';

/**
 * A card that composes lit-button children in its actions row.
 *
 * @summary Composite card with actions.
 * @slot eyebrow - Short label above the title.
 * @slot heading - The card title.
 * @slot - Body text.
 * @slot actions - lit-button elements.
 * @csspart base - The card container.
 * @cssprop --exp-card-padding - Inner padding.
 * @cssprop --exp-card-radius - Corner radius.
 */
export class LitCard extends LitElement {
  static override styles = css`:host { display: block; } [hidden] { display: none !important; }`;
  static override properties = {
    tone: { type: String, reflect: true },
    headingLevel: { type: Number, attribute: 'heading-level' },
    empty: { state: true, attribute: false },
  };

  /** Elevated or outlined. */
  tone: 'raised' | 'plain' = 'raised';
  /** Heading level for the title (2–6). */
  headingLevel = 3;
  /** @internal */
  private empty: Record<string, boolean> = {};

  override render() {
    const level = Math.min(6, Math.max(2, this.headingLevel || 3));
    return html`${stylesheet('card.css')}
      <article part="base" class="exp-card exp-card--${this.tone}">
        <p class="exp-card__eyebrow" ?hidden=${this.empty.eyebrow}><slot name="eyebrow" @slotchange=${this.sync}></slot></p>
        <div class="exp-card__title" role="heading" aria-level=${level}><slot name="heading"></slot></div>
        <p class="exp-card__body" ?hidden=${this.empty.body}><slot @slotchange=${this.sync}></slot></p>
        <div class="exp-card__actions" ?hidden=${this.empty.actions}><slot name="actions" @slotchange=${this.sync}></slot></div>
      </article>`;
  }

  // slotchange doesn't fire for a slot that starts empty, so check once on first render.
  override firstUpdated() {
    for (const slot of this.renderRoot.querySelectorAll('slot')) this.sync({ target: slot } as unknown as Event);
  }

  private sync(event: Event) {
    const slot = event.target as HTMLSlotElement;
    const key = slot.name || 'body';
    const isEmpty = slot.assignedNodes({ flatten: true })
      .every((node) => node.nodeType === Node.TEXT_NODE && !node.textContent?.trim());
    if (this.empty[key] !== isEmpty) this.empty = { ...this.empty, [key]: isEmpty };
  }
}

customElements.define('lit-card', LitCard);

declare global {
  interface HTMLElementTagNameMap { 'lit-card': LitCard; }
}
