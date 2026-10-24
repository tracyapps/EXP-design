// Fixture-only adapter (not part of the library API): lets the comparison page
// render a named component with props in a plain browser page.
import { createElement, type ComponentType } from 'react';
import { createRoot } from 'react-dom/client';
import { Accordion, Button, Card } from './index';

const components: Record<string, ComponentType<any>> = { button: Button, card: Card, accordion: Accordion };

export function mount(target: Element, name: string, props: Record<string, unknown>) {
  const component = components[name];
  if (!component) throw new Error(`Unknown component: ${name}`);
  const { label, ...rest } = props;
  const root = createRoot(target);
  root.render(createElement(component, rest, label as string | undefined));
  return () => root.unmount();
}
