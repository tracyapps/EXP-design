import { ChangeDetectionStrategy, Component, ViewEncapsulation, computed, input } from '@angular/core';
import { ButtonComponent } from './button.component';

export type CardAction = { label: string; appearance?: 'primary' | 'secondary' | 'ghost'; size?: 's' | 'm' | 'l' };

/** Composite card: composes ButtonComponent children. Styles: styles/card.css */
@Component({
  selector: 'ex-card',
  imports: [ButtonComponent],
  encapsulation: ViewEncapsulation.None,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { style: 'display: block' },
  template: `
    <article [class]="'exp-card exp-card--' + tone()">
      @if (eyebrow()) { <p class="exp-card__eyebrow">{{ eyebrow() }}</p> }
      <div class="exp-card__title" role="heading" [attr.aria-level]="level()">{{ title() }}</div>
      @if (body()) { <p class="exp-card__body">{{ body() }}</p> }
      @if (actions().length) {
        <div class="exp-card__actions">
          @for (action of actions(); track action.label) {
            <ex-button [appearance]="action.appearance ?? 'primary'" [size]="action.size ?? 'm'">{{ action.label }}</ex-button>
          }
        </div>
      }
    </article>
  `,
})
export class CardComponent {
  /** Short label above the title. */
  readonly eyebrow = input<string>();
  /** The card title. */
  readonly title = input.required<string>();
  /** Body text. */
  readonly body = input<string>();
  /** Elevated or outlined. */
  readonly tone = input<'raised' | 'plain'>('raised');
  /** Heading level for the title (2–6). */
  readonly headingLevel = input<number>(3);
  /** Buttons rendered in the actions row. */
  readonly actions = input<CardAction[]>([]);

  protected readonly level = computed(() => Math.min(6, Math.max(2, this.headingLevel())));
}
