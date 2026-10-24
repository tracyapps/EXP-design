// Each component links its stylesheet inside its own shadow root, so the CSS
// stays a plain, editable file (styles/*.css). Tokens come from the page's
// styles/tokens.css: custom properties inherit through shadow boundaries.
export function styleLink(file) {
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = new URL(`../styles/${file}`, import.meta.url).href;
  return link;
}

let counter = 0;
export const uid = (prefix) => `${prefix}-${++counter}`;
