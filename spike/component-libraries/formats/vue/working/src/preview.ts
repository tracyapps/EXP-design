// Fixture-only adapter (not part of the library API) for the comparison page.
import { createApp, h, type Component } from 'vue';
import { ExpAccordion, ExpButton, ExpCard } from './index';

const components: Record<string, Component> = { button: ExpButton, card: ExpCard, accordion: ExpAccordion };

export function mount(target: Element, name: string, props: Record<string, unknown>) {
  const component = components[name];
  if (!component) throw new Error(`Unknown component: ${name}`);
  const { label, ...rest } = props;
  const app = createApp({ render: () => h(component, rest, label ? { default: () => label as string } : undefined) });
  app.mount(target);
  return () => app.unmount();
}
