// Referral context stays in explicit navigation URLs, never a tracking cookie.
export function incomingReferral() {
  const code = new URLSearchParams(window.location.search).get('ref');
  return /^[A-Za-z0-9_-]{32}$/.test(code || '') ? code : null;
}
export function withReferral(path) {
  const code = incomingReferral();
  if (!code) return path;
  const url = new URL(path, window.location.origin);
  url.searchParams.set('ref', code);
  return `${url.pathname}${url.search}${url.hash}`;
}
export const registrationHref = (alsoPro = false) => withReferral(`/account?intent=register${alsoPro ? '&next=pro' : ''}`);
