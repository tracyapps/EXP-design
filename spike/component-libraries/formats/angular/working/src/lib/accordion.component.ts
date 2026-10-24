import { ChangeDetectionStrategy, Component, ViewEncapsulation, input, linkedSignal } from '@angular/core';
import { AccordionItemComponent } from './accordion-item.component';

export type AccordionEntry = { title: string; content: string; open?: boolean };

/** Accordion container made of AccordionItemComponent children. Styles: styles/accordion.css */
@Component({
  selector: 'ex-accordion',
  imports: [AccordionItemComponent],
  encapsulation: ViewEncapsulation.None,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { style: 'display: block' },
  template: `
    <div class="exp-accordion">
      @for (item of items(); track item.title; let index = $index) {
        <ex-accordion-item [title]="item.title" [open]="openState()[index]"
          [headingLevel]="headingLevel()" (toggle)="toggleAt(index)">
          <p>{{ item.content }}</p>
        </ex-accordion-item>
      }
    </div>
  `,
})
export class AccordionComponent {
  /** Sections. */
  readonly items = input.required<AccordionEntry[]>();
  /** Allow more than one open section. */
  readonly allowMultiple = input(false);
  /** Heading level for every section title (2–6). */
  readonly headingLevel = input(3);

  protected readonly openState = linkedSignal(() => this.items().map((item) => Boolean(item.open)));

  protected toggleAt(index: number) {
    this.openState.update((state) =>
      state.map((value, i) => (i === index ? !value : this.allowMultiple() ? value : false)));
  }
}
