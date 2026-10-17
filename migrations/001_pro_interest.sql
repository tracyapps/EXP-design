-- Apply manually to the dedicated private launch database after review.
-- This schema is never exposed through a browser-facing database API.
BEGIN;
CREATE TABLE exp_pro_interest (
  email text PRIMARY KEY CHECK (email = lower(email) AND length(email) <= 254),
  model_preference text NOT NULL CHECK (model_preference IN ('one_time', 'subscription', 'either')),
  purpose text NOT NULL DEFAULT 'pro_interest' CHECK (purpose = 'pro_interest'),
  offer_version text NOT NULL CHECK (offer_version = 'pro-discovery-v1'),
  consent_version text NOT NULL CHECK (consent_version = 'pro-interest-v1'),
  source text NOT NULL CHECK (source = 'pro page'),
  requested_at timestamptz NOT NULL DEFAULT now(),
  retry_after timestamptz NOT NULL DEFAULT now() + interval '10 minutes',
  expires_at timestamptz NOT NULL,
  token_hash text UNIQUE,
  withdrawal_hash text NOT NULL UNIQUE,
  confirmed_at timestamptz,
  withdrawn_at timestamptz,
  CHECK (token_hash IS NULL OR token_hash ~ '^[a-f0-9]{64}$'),
  CHECK (withdrawal_hash ~ '^[a-f0-9]{64}$')
);
REVOKE ALL ON exp_pro_interest FROM PUBLIC;
CREATE INDEX exp_pro_interest_active ON exp_pro_interest (confirmed_at)
  WHERE confirmed_at IS NOT NULL AND withdrawn_at IS NULL;
COMMIT;
