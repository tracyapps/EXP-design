import { html } from 'lit';

/**
 * Components link their stylesheet inside the shadow root so the CSS stays a
 * plain, editable file in styles/. After bundling, import.meta.url is
 * dist/index.js, so ../styles/ still resolves next to it.
 */
export const stylesheet = (file: string) =>
  html`<link rel="stylesheet" href=${new URL(`../styles/${file}`, import.meta.url).href} />`;

let counter = 0;
export const uid = (prefix: string) => `${prefix}-${++counter}`;
