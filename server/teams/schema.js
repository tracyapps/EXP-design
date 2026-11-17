// Shared vocabulary, with server-side validation independent of browser controls.
export const options = {
  role: ['designer', 'design-system lead', 'developer / design engineer', 'team leader', 'IT / security / procurement', 'other', 'not sure'],
  size: ['just me', '2–5', '6–20', '21–100', '100+', 'not sure'],
  systems: ['Mac', 'Windows', 'Linux', 'not sure'],
  tools: ['design tools', 'coded component libraries', 'Storybook / component docs', 'design tokens', 'repositories / delivery tools', 'other', 'not sure'],
  barrier: ['moving existing work', 'working with the rest of the team', 'IT / security approval', 'missing features', 'cost', 'time to try it', 'nothing obvious', 'other', 'not sure'],
};
export const textFields = { problem: 1500, stack: 1000, approval: 1000 };
export function validateAnswers(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const keys = [...Object.keys(options), ...Object.keys(textFields)];
  if (Object.keys(value).some(key => !keys.includes(key))) return null;
  const result = {};
  for (const key of ['role', 'size', 'barrier']) {
    const answer = value[key] ?? '';
    if (typeof answer !== 'string' || (answer && !options[key].includes(answer))) return null;
    result[key] = answer;
  }
  for (const key of ['systems', 'tools']) {
    const answer = value[key] ?? [];
    if (!Array.isArray(answer) || answer.length > options[key].length ||
      answer.some(item => !options[key].includes(item)) || new Set(answer).size !== answer.length) return null;
    if (answer.includes('not sure') && answer.length > 1) return null;
    result[key] = answer;
  }
  for (const [key, limit] of Object.entries(textFields)) {
    const answer = value[key] ?? '';
    if (typeof answer !== 'string' || answer.length > limit || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(answer)) return null;
    result[key] = answer.trim();
  }
  return Object.values(result).some(answer => answer.length > 0) ? result : null;
}
