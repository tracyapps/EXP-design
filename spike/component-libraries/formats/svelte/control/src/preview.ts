// Fixture-only adapter (not part of the library API) for the comparison page.
import { createRawSnippet, mount as svelteMount, unmount, type Component } from 'svelte';
import { Accordion, Button, Card } from './index';

const components: Record<string, Component<any>> = { button: Button, card: Card, accordion: Accordion };
const escape = (text: string) => text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

export function mount(target: Element, name: string, props: Record<string, unknown>) {
  const component = components[name];
  if (!component) throw new Error(`Unknown component: ${name}`);
  const { label, ...rest } = props;
  const children = typeof label === 'string'
    ? createRawSnippet(() => ({ render: () => `<span>${escape(label)}</span>` }))
    : undefined;
  const instance = svelteMount(component, { target, props: { ...rest, children } });
  return () => unmount(instance);
}
