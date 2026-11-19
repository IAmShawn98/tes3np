// Report sign-in progress without reading fields or changing Discord's handlers.
(() => {
  if (window.top !== window || location.origin !== 'https://discord.com') return;
  let watchAttempt;
  const announce = state => {
    try { chrome.webview.postMessage(state); } catch {}
  };
  const errorsIn = form => [...form.querySelectorAll('[aria-invalid="true"], [class*="errorMessage_"], [role="alert"]')]
    .filter(element => element.getClientRects().length > 0)
    .map(element => element.textContent.trim() || (element.getAttribute('aria-invalid') === 'true' ? 'invalid' : ''))
    .filter(Boolean).join('\n');

  document.addEventListener('submit', event => {
    const form = event.target;
    if (!event.isTrusted || location.pathname !== '/login' ||
        !form.matches('form') || !form.querySelector('input[type=password]')) return;
    watchAttempt?.disconnect();
    announce('tes3np-sign-in-started');
    const originalErrors = errorsIn(form);
    const observer = new MutationObserver(() => {
      if (location.pathname !== '/login' || !form.isConnected ||
          !form.querySelector('input[type=password]')) {
        observer.disconnect();
        return;
      }
      const errors = errorsIn(form);
      if (errors && errors !== originalErrors) {
        observer.disconnect();
        announce('tes3np-sign-in-rejected');
      }
    });
    watchAttempt = observer;
    observer.observe(form, { subtree: true, childList: true, characterData: true,
      attributes: true, attributeFilter: ['aria-invalid', 'class'] });
    setTimeout(() => observer.disconnect(), 30000);
  }, true);
})()
