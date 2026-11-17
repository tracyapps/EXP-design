BEGIN;
-- Account-free team research. No relationship to account/news/Pro permissions.
CREATE TABLE IF NOT EXISTS exp_team_research (
  capability_hash text PRIMARY KEY CHECK (length(capability_hash)=64),
  answers jsonb NOT NULL,
  survey_version text NOT NULL DEFAULT 'team-research-v1',
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '90 days',
  email text,
  consent_version text,
  requested_at timestamptz,
  confirmed_at timestamptz,
  confirmation_hash text,
  confirmation_expires_at timestamptz,
  retry_after timestamptz,
  CHECK ((email IS NULL AND consent_version IS NULL) OR
    (email IS NOT NULL AND consent_version='team-research-contact-v1'))
);
CREATE INDEX IF NOT EXISTS exp_team_research_expiry ON exp_team_research(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS exp_team_research_confirmation ON exp_team_research(confirmation_hash)
  WHERE confirmation_hash IS NOT NULL;
-- Shared serverless abuse budgets. Keys contain a fixed operation or email hash,
-- never IP addresses, raw email, account ids, or browser identifiers.
CREATE TABLE IF NOT EXISTS exp_team_research_limit (
  key text PRIMARY KEY,
  started_at timestamptz NOT NULL DEFAULT now(),
  count integer NOT NULL DEFAULT 1
);
REVOKE ALL ON exp_team_research, exp_team_research_limit FROM PUBLIC;
COMMIT;
