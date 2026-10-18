-- Private drafts plus explicit public snapshots. Apply after 003.
BEGIN;
CREATE TABLE exp_member_community (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  handle text NOT NULL UNIQUE CHECK (handle ~ '^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$'),
  display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 80),
  bio text NOT NULL CHECK (length(bio) <= 500),
  link text NOT NULL CHECK (length(link) <= 300),
  revision uuid NOT NULL DEFAULT pg_catalog.gen_random_uuid(),
  first_published_at timestamptz,
  published_at timestamptz,
  published_revision uuid,
  published_name text,
  published_bio text,
  published_link text,
  publication_version text,
  moderation_hold boolean NOT NULL DEFAULT false,
  CHECK ((published_at IS NULL AND published_revision IS NULL AND published_name IS NULL AND published_bio IS NULL AND published_link IS NULL AND publication_version IS NULL)
    OR (published_at IS NOT NULL AND published_revision IS NOT NULL AND published_name IS NOT NULL AND published_bio IS NOT NULL AND published_link IS NOT NULL AND publication_version='community-profile-v1'))
);
CREATE TABLE exp_member_community_report (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  target_id uuid NOT NULL REFERENCES exp_member_community(user_id) ON DELETE CASCADE,
  target_revision uuid NOT NULL,
  category text NOT NULL CHECK (category IN ('spam','harassment','privacy','other')),
  reason text NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  public_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reporter_id, target_id, target_revision)
);
CREATE INDEX exp_member_community_report_target_idx ON exp_member_community_report(target_id, created_at);
CREATE TABLE exp_member_community_limit (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  count integer NOT NULL CHECK (count > 0)
);
REVOKE ALL ON exp_member_community, exp_member_community_report, exp_member_community_limit FROM PUBLIC;
COMMIT;
