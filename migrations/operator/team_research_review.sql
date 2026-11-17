-- Read-only operator view. Never expose through a public endpoint or publish output.
-- All current answers; email is available ONLY for separately confirmed follow-up.
SELECT created_at, expires_at, answers,
  CASE WHEN confirmed_at IS NOT NULL THEN email ELSE NULL END AS research_followup_email,
  confirmed_at, consent_version
FROM exp_team_research
WHERE expires_at > now()
ORDER BY created_at DESC;
-- Re-run immediately before contacting anyone; do not reuse an exported list
-- after permission could have been withdrawn. No general marketing permission.
