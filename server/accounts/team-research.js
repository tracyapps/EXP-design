// Owner-selected mailbox. This is checked against Better Auth's verified server
// session, never a browser-supplied email or a profile/display-name field.
export const teamResearchOwnerEmail = 'tracyapps@gmail.com';
export const teamResearchActions = { 'team-research-responses': ['before'] };
export function canReviewTeamResearch(user) {
  return Boolean(user?.id && user.emailVerified === true &&
    typeof user.email === 'string' && user.email.trim().toLowerCase() === teamResearchOwnerEmail);
}
export async function handleTeamResearch({ user, body, store }) {
  if (!canReviewTeamResearch(user)) return { status: 403, body: { error: 'This inbox is only available to the EXP owner.' } };
  if (body.before !== undefined && (typeof body.before !== 'string' || !/^[1-9][0-9]{0,18}$/.test(body.before) || BigInt(body.before)>9223372036854775807n))
    return { status: 400, body: { error: 'Reload the inbox to continue.' } };
  if (!store) return { status: 503, body: { error: 'The research inbox is not connected yet.' } };
  const { responses, nextBefore } = await store.listResponses(body.before ?? null);
  return { status: 200, body: { ok: true, responses, nextBefore } };
}
