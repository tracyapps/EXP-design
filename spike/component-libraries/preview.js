// Renders one component from one copy (working or control) of one format.
// Loaded in an iframe by compare.html so the two copies never share custom
// element registries, frameworks or CSS.
//   preview.html?format=react&copy=working&component=card&theme=dark&frame=left
const params = new URLSearchParams(location.search);
const formatId = params.get('format');
const copy = params.get('copy') === 'control' ? 'control' : 'working';
const componentId = params.get('component');
const theme = params.get('theme');
const frame = params.get('frame') ?? '';
const demos = document.getElementById('demos');

if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;

function report(type, detail = {}) {
  parent.postMessage({ source: 'exp-preview', frame, type, ...detail }, location.origin);
}

function showError(error) {
  const box = document.createElement('p');
  box.className = 'error';
  box.setAttribute('role', 'alert');
  box.textContent = `Couldn't render ${componentId} from ${formatId}/${copy}: ${error?.message ?? error}`;
  demos.replaceChildren(box);
  report('error', { message: String(error?.message ?? error) });
}

const loadStyle = (href) => new Promise((resolve) => {
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  link.onload = link.onerror = resolve;
  document.head.append(link);
});

function figure(caption, wide) {
  const fig = document.createElement('figure');
  if (wide) fig.className = 'wide';
  const stage = document.createElement('div');
  const cap = document.createElement('figcaption');
  cap.textContent = caption;
  fig.append(stage, cap);
  demos.append(fig);
  return stage;
}

// Custom-element formats: build light-DOM children the way a page author would.
function element(prefix, component, props) {
  const el = (name, attrs = {}, children = []) => {
    const node = document.createElement(`${prefix}-${name}`);
    for (const [key, value] of Object.entries(attrs)) {
      if (value === true) node.setAttribute(key, '');
      else if (value !== undefined && value !== false && value !== null) node.setAttribute(key, String(value));
    }
    node.append(...children);
    return node;
  };
  const slotted = (slot, text, tag = 'span') => {
    const node = document.createElement(tag);
    node.slot = slot;
    node.textContent = text;
    return node;
  };
  switch (component) {
    case 'button':
      return el('button', { appearance: props.appearance, size: props.size, disabled: props.disabled }, [props.label]);
    case 'card': {
      const children = [];
      if (props.eyebrow) children.push(slotted('eyebrow', props.eyebrow));
      children.push(slotted('heading', props.title));
      if (props.body) children.push(props.body);
      for (const action of props.actions ?? []) {
        const button = el('button', { appearance: action.appearance, size: action.size }, [action.label]);
        button.slot = 'actions';
        children.push(button);
      }
      return el('card', { tone: props.tone, 'heading-level': props.headingLevel }, children);
    }
    case 'accordion':
      return el('accordion', { 'allow-multiple': props.allowMultiple, 'heading-level': props.headingLevel },
        props.items.map((item) => {
          const p = document.createElement('p');
          p.textContent = item.content;
          return el('accordion-item', { heading: item.title, open: item.open }, [p]);
        }));
    default:
      throw new Error(`No element mapping for ${component}`);
  }
}

async function main() {
  const library = await (await fetch('library.json', { cache: 'no-store' })).json();
  const format = library.formats.find((f) => f.id === formatId);
  const component = library.components.find((c) => c.id === componentId);
  if (!format || !component) throw new Error('Unknown format or component');
  const base = new URL(`formats/${format.id}/${copy}/`, location.href);
  document.title = `${format.title} · ${component.title} · ${copy}`;

  await Promise.all(format.styles.map((path) => loadStyle(new URL(path, base))));
  const wide = component.id === 'accordion';

  if (format.mode === 'snippet') {
    const path = format.files[component.id][0];
    const html = await (await fetch(new URL(path, base), { cache: 'no-store' })).text();
    const stage = figure(`As written in ${path}`, true);
    stage.innerHTML = html;
    if (format.script) (await import(new URL(format.script, base))).enhanceAccordions(stage);
  } else if (format.mode === 'elements') {
    await import(new URL(format.entry, base));
    for (const demo of component.demos) figure(demo.caption, wide).append(element(format.prefix, component.id, demo.props));
  } else if (format.mode === 'mount') {
    const { mount } = await import(new URL(format.entry, base));
    for (const demo of component.demos) mount(figure(demo.caption, wide), component.id, structuredClone(demo.props));
  } else if (format.mode === 'mount-global') {
    await import(new URL(format.entry, base));
    const { mount } = globalThis.expFixture ?? {};
    if (!mount) throw new Error(`${format.entry} did not register globalThis.expFixture`);
    for (const demo of component.demos) await mount(figure(demo.caption, wide), component.id, structuredClone(demo.props));
  }

  // Report size changes so the parent can fit the iframe (accordions grow).
  const observer = new ResizeObserver(() => report('size', { height: document.documentElement.scrollHeight }));
  observer.observe(document.body);
  report('ready');
}

window.addEventListener('error', (event) => showError(event.error ?? event.message));
main().catch(showError);
