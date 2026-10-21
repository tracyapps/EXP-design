-- Optional account feedback, sharing and consented signup credit. Apply after 003.
-- No mail enrollment, entitlement, public testimonial or rewards are created.
BEGIN;
CREATE TABLE exp_member_share_link (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE CHECK (code ~ '^[A-Za-z0-9_-]{32}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE exp_member_share_event (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  target text NOT NULL CHECK (target IN ('copy','system','email','linkedin','bluesky','facebook','mastodon')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX exp_member_share_event_user_idx ON exp_member_share_event(user_id, created_at);
CREATE TABLE exp_member_referral_credit (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  referrer_id uuid REFERENCES exp_member_user(id) ON DELETE SET NULL,
  consent_version text NOT NULL CHECK (consent_version='referral-credit-v1'),
  accepted_at timestamptz NOT NULL DEFAULT now(),
  withdrawn_at timestamptz,
  CHECK (referrer_id IS NULL OR referrer_id<>user_id)
);
CREATE INDEX exp_member_referral_credit_referrer_idx ON exp_member_referral_credit(referrer_id) WHERE withdrawn_at IS NULL;
CREATE TABLE exp_member_feedback (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('feedback','feature')),
  subject text NOT NULL CHECK (length(trim(subject)) BETWEEN 1 AND 120),
  message text NOT NULL CHECK (length(trim(message)) BETWEEN 1 AND 1500),
  testimonial_allowed boolean NOT NULL DEFAULT false,
  testimonial_name text CHECK (length(testimonial_name)<=70),
  consent_version text,
  accepted_at timestamptz,
  withdrawn_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT testimonial_allowed OR (testimonial_name IS NOT NULL AND consent_version='testimonial-v1' AND accepted_at IS NOT NULL AND withdrawn_at IS NULL))
);
CREATE INDEX exp_member_feedback_user_idx ON exp_member_feedback(user_id, created_at DESC);
CREATE TABLE exp_member_engagement_limit (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  count integer NOT NULL CHECK (count>0)
);
REVOKE ALL ON exp_member_share_link, exp_member_share_event, exp_member_referral_credit,
  exp_member_feedback, exp_member_engagement_limit FROM PUBLIC;
COMMIT;
