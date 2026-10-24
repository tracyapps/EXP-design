// Progressive enhancement for .exp-accordion (APG accordion pattern).
// Without this script every panel stays visible and readable.
export function enhanceAccordions(root = document) {
  for (const accordion of root.querySelectorAll('[data-exp-accordion]')) {
    if (accordion.dataset.enhanced) continue;
    accordion.dataset.enhanced = 'true';
    const allowMultiple = accordion.hasAttribute('data-allow-multiple');
    const triggers = [...accordion.querySelectorAll('.exp-accordion__trigger')];
    for (const trigger of triggers) {
      const panel = accordion.querySelector('#' + CSS.escape(trigger.getAttribute('aria-controls')));
      if (panel?.hasAttribute('data-start-closed')) {
        panel.hidden = true;
        trigger.setAttribute('aria-expanded', 'false');
      }
      trigger.addEventListener('click', () => {
        const open = trigger.getAttribute('aria-expanded') !== 'true';
        if (open && !allowMultiple) {
          for (const other of triggers) if (other !== trigger) setOpen(accordion, other, false);
        }
        setOpen(accordion, trigger, open);
      });
    }
  }
}

function setOpen(accordion, trigger, open) {
  trigger.setAttribute('aria-expanded', String(open));
  const panel = accordion.querySelector('#' + CSS.escape(trigger.getAttribute('aria-controls')));
  if (panel) panel.hidden = !open;
}
