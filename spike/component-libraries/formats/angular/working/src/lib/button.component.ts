import { ChangeDetectionStrategy, Component, ViewEncapsulation, input } from '@angular/core';

/** Simple action button. The label is projected content. Styles: styles/button.css */
@Component({
  selector: 'ex-button',
  encapsulation: ViewEncapsulation.None,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { style: 'display: inline-block' },
  template: `
    <button type="button" [class]="'exp-button exp-button--' + appearance() + ' exp-button--' + size()"
      [disabled]="disabled()"><ng-content /></button>
  `,
})
export class ButtonComponent {
  /** Visual emphasis. */
  readonly appearance = input<'primary' | 'secondary' | 'ghost'>('primary');
  /** Size. */
  readonly size = input<'s' | 'm' | 'l'>('m');
  /** Disables the button. */
  readonly disabled = input(false);
}
