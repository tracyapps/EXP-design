-- Account database, after 003. Additive; no startup migration or hosted grants.
BEGIN;
CREATE TABLE exp_member_news (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  enabled boolean NOT NULL,
  permission_version text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
-- Operator-managed grants. Runtime role must have SELECT only on this table.
CREATE TABLE exp_member_support_grant (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  granted_at timestamptz NOT NULL DEFAULT now(),
  operator_reference text NOT NULL CHECK (length(trim(operator_reference)) BETWEEN 1 AND 120)
);
CREATE TABLE exp_member_ticket (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES exp_member_user(id) ON DELETE CASCADE,
  subject text NOT NULL CHECK (length(trim(subject)) BETWEEN 1 AND 120),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX exp_member_ticket_owner_idx ON exp_member_ticket(user_id, updated_at DESC, id);
CREATE INDEX exp_member_ticket_queue_idx ON exp_member_ticket(updated_at DESC, id);
CREATE TABLE exp_member_ticket_event (
  id uuid PRIMARY KEY,
  ticket_id uuid NOT NULL REFERENCES exp_member_ticket(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES exp_member_user(id) ON DELETE SET NULL,
  actor_kind text NOT NULL CHECK (actor_kind IN ('author','support')),
  kind text NOT NULL CHECK (kind IN ('opened','reply','open','closed')),
  message text NOT NULL CHECK (length(message) <= 1500 AND
    ((kind IN ('opened','reply') AND length(trim(message)) > 0) OR
     (kind IN ('open','closed') AND message = ''))),
  sequence integer NOT NULL CHECK (sequence > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ticket_id, sequence)
);
CREATE INDEX exp_member_ticket_event_actor_idx ON exp_member_ticket_event(actor_id);
CREATE TABLE exp_member_ticket_limit (
  user_id uuid PRIMARY KEY REFERENCES exp_member_user(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  count integer NOT NULL CHECK (count > 0)
);
-- Private accountability for staff thread reads/replies/status changes.
CREATE TABLE exp_member_support_audit (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES exp_member_ticket(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES exp_member_user(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN ('read','reply','open','closed')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX exp_member_support_audit_ticket_idx ON exp_member_support_audit(ticket_id, created_at);
CREATE INDEX exp_member_support_audit_actor_idx ON exp_member_support_audit(actor_id);
REVOKE ALL ON exp_member_news, exp_member_support_grant, exp_member_ticket,
  exp_member_ticket_event, exp_member_ticket_limit, exp_member_support_audit FROM PUBLIC;
COMMIT;
