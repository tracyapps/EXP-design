-- Optional owner-only exception for the reserved tapps handle. Apply after 007.
-- Operators bind the verified owner explicitly; the app can only read this table.
BEGIN;
CREATE TABLE exp_member_community_reservation (
  handle text PRIMARY KEY CHECK (handle='tapps'),
  user_id uuid NOT NULL UNIQUE REFERENCES exp_member_user(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON exp_member_community_reservation FROM PUBLIC;
COMMIT;
