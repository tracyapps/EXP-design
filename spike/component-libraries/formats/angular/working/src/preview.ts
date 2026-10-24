// Fixture-only adapter (not part of the library API) for the comparison page.
// Exposes globalThis.expFixture.mount(target, name, props).
import { createComponent, provideZonelessChangeDetection, type Type } from '@angular/core';
import { createApplication } from '@angular/platform-browser';
import { AccordionComponent, ButtonComponent, CardComponent } from './public-api';

const components: Record<string, { type: Type<unknown>; tag: string }> = {
  button: { type: ButtonComponent, tag: 'ex-button' },
  card: { type: CardComponent, tag: 'ex-card' },
  accordion: { type: AccordionComponent, tag: 'ex-accordion' },
};
const application = createApplication({ providers: [provideZonelessChangeDetection()] });

async function mount(target: Element, name: string, props: Record<string, unknown>) {
  const entry = components[name];
  if (!entry) throw new Error(`Unknown component: ${name}`);
  const app = await application;
  const host = document.createElement(entry.tag);
  target.append(host);
  const { label, ...inputs } = props;
  const ref = createComponent(entry.type, {
    environmentInjector: app.injector,
    hostElement: host,
    projectableNodes: typeof label === 'string' ? [[document.createTextNode(label)]] : undefined,
  });
  for (const [key, value] of Object.entries(inputs)) ref.setInput(key, value);
  app.attachView(ref.hostView);
  ref.changeDetectorRef.detectChanges();
  return () => { app.detachView(ref.hostView); ref.destroy(); };
}

(globalThis as { expFixture?: unknown }).expFixture = { mount };
