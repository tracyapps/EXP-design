import { ChangeDetectionStrategy, Component, ViewEncapsulation, input, output } from '@angular/core';

let counter = 0;

/**
 * One accordion section (child of AccordionComponent). WAI-ARIA APG accordion
 * pattern: a button inside a heading with aria-expanded/aria-controls, and a
 * region panel labelled by that button.
 */
@Component({
  selector: 'ex-accordion-item',
  encapsulation: ViewEncapsulation.None,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="exp-accordion__item">
      <div class="exp-accordion__heading" role="heading" [attr.aria-level]="headingLevel()">
        <button type="button" class="exp-accordion__trigger" [id]="uid + '-trigger'"
          [attr.aria-expanded]="open()" [attr.aria-controls]="uid + '-panel'" (click)="toggle.emit()">
          <span>{{ title() }}</span>
          <span class="exp-accordion__icon" aria-hidden="true"></span>
        </button>
      </div>
      <div class="exp-accordion__panel" [id]="uid + '-panel'" role="region"
        [attr.aria-labelledby]="uid + '-trigger'" [hidden]="!open()"><ng-content /></div>
    </div>
  `,
})
export class AccordionItemComponent {
  /** The section title. */
  readonly title = input.required<string>();
  /** Whether the panel is shown. */
  readonly open = input(false);
  /** Heading level (set by AccordionComponent). */
  readonly headingLevel = input(3);
  /** Emitted when the header button is activated. */
  readonly toggle = output<void>();

  protected readonly uid = `ex-accordion-${++counter}`;
}
