// Optional enhancement: handles and payment links remain usable without JS.
if (navigator.clipboard?.writeText) {
  const status = document.getElementById('copy-status');
  for (const button of document.querySelectorAll('[data-copy]')) {
    button.hidden = false;
    button.addEventListener('click', async () => {
      status.textContent = '';
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
        status.textContent = `Copied ${button.dataset.copy}`;
      } catch {
        status.textContent = 'Copy did not work. Select the handle above to copy it.';
      }
    });
  }
}
