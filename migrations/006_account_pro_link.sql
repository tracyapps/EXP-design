-- Account-side reference only; the separate Pro ledger owns email permission.
BEGIN;
CREATE TABLE exp_member_pro_link (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  interest_ref text NOT NULL UNIQUE CHECK (interest_ref ~ '^[a-f0-9]{64}$'),
  link_version text NOT NULL CHECK (link_version = 'pro-account-link-v1'),
  linked_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON exp_member_pro_link FROM PUBLIC;
COMMIT;
