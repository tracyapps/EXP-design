-- Account DB, after 003/005/007/008. Additive; never run at application startup.
BEGIN;
CREATE TABLE exp_member_ticket_preference (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  email_alerts boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE exp_member_ticket_mail (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES exp_member_ticket_event(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  audience text NOT NULL CHECK (audience IN ('author','support')),
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','accepted','failed','skipped')),
  created_at timestamptz NOT NULL DEFAULT now(),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  first_attempt_at timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  lease_id uuid,
  lease_until timestamptz,
  mail jsonb,
  provider_id text,
  finished_at timestamptz,
  outcome text CHECK (outcome IN ('accepted','ineligible','expired','attempt-limit','provider-rejected')),
  UNIQUE (event_id, recipient_id)
);
CREATE INDEX exp_member_ticket_mail_pending_idx ON exp_member_ticket_mail(next_attempt_at, id) WHERE state='pending';
CREATE INDEX exp_member_ticket_mail_recipient_idx ON exp_member_ticket_mail(recipient_id);
CREATE INDEX exp_member_ticket_mail_finished_idx ON exp_member_ticket_mail(finished_at) WHERE state<>'pending';
CREATE INDEX exp_member_ticket_closed_retention_idx ON exp_member_ticket(updated_at, id) WHERE status='closed';
CREATE INDEX exp_member_session_expiry_idx ON exp_member_session("expiresAt");
CREATE INDEX exp_member_verification_expiry_idx ON exp_member_verification("expiresAt");
CREATE INDEX exp_member_rate_retention_idx ON exp_member_rate_limit("lastRequest");
CREATE INDEX exp_member_mail_retention_idx ON exp_member_mail_limit(sent_at);
CREATE INDEX exp_member_beta_feedback_retention_idx ON exp_member_beta_feedback(created_at);
CREATE INDEX exp_member_support_audit_retention_idx ON exp_member_support_audit(created_at);
-- A report is never expired merely because nobody reviewed it.
ALTER TABLE exp_member_community_report ADD COLUMN resolved_at timestamptz;
CREATE INDEX exp_member_report_retention_idx ON exp_member_community_report(resolved_at) WHERE resolved_at IS NOT NULL;
REVOKE ALL ON exp_member_ticket_preference, exp_member_ticket_mail FROM PUBLIC;
COMMIT;
