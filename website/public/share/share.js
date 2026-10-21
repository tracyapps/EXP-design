const status=document.getElementById('copy-status');
for(const button of document.querySelectorAll('[data-copy-target]')){
  button.hidden=false;
  button.addEventListener('click',async()=>{
    const target=document.getElementById(button.dataset.copyTarget);
    try{await navigator.clipboard.writeText(target.textContent.trim());status.textContent='Copied. Make it sound like you, and share away.';}
    catch{status.textContent='Copying isn’t available here. The text is selected; use your browser’s Copy command.';const range=document.createRange();range.selectNodeContents(target);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);}
  });
}
