BEGIN;
-- Private inbox identifiers are deliberately unrelated to respondent capabilities.
ALTER TABLE exp_team_research
  ADD COLUMN response_id bigint GENERATED ALWAYS AS IDENTITY,
  ADD COLUMN owner_notified_at timestamptz,
  ADD COLUMN owner_notify_claim text,
  ADD COLUMN owner_notify_after timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN owner_notify_attempts integer NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX exp_team_research_response_id ON exp_team_research(response_id);
CREATE INDEX exp_team_research_owner_queue ON exp_team_research(owner_notify_after)
  WHERE owner_notified_at IS NULL;
COMMIT;
