export default async function accountRequest(body) {
  const response = await fetch('/api/account', { method: body ? 'POST' : 'GET', credentials: 'same-origin',
    cache: 'no-store', signal: AbortSignal.timeout(15000),
    headers: body ? { 'content-type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.ok !== true) {
    const error = new Error(result.error || 'Account service is unavailable. Please try later.');
    error.status = response.status; error.field = result.field; throw error;
  }
  return result;
}
