-- Private beta choices and text feedback. Apply after 003, before enabling this slice.
BEGIN;
CREATE TABLE exp_member_beta (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  participating boolean NOT NULL,
  invite_emails boolean NOT NULL CHECK (NOT invite_emails OR participating),
  permission_version text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE exp_member_beta_feedback (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  subject text NOT NULL CHECK (length(trim(subject)) BETWEEN 1 AND 120),
  message text NOT NULL CHECK (length(trim(message)) BETWEEN 1 AND 1500),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX exp_member_beta_feedback_user_idx ON exp_member_beta_feedback(user_id, created_at DESC, id);
CREATE TABLE exp_member_beta_limit (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  count integer NOT NULL CHECK (count > 0)
);
REVOKE ALL ON exp_member_beta, exp_member_beta_feedback, exp_member_beta_limit FROM PUBLIC;
COMMIT;
