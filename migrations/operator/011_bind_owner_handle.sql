-- Operator only. Apply after 011 and review the existing verified owner grant.
-- Does not grant support access or publish a profile. Refuses ambiguous ownership.
BEGIN;
DO $owner_handle$
DECLARE owner_id uuid;
BEGIN
  IF current_database()<>'exp_accounts' THEN RAISE EXCEPTION 'Select exp_accounts first'; END IF;
  SELECT u.id INTO STRICT owner_id
    FROM exp_member_user u JOIN exp_member_support_grant g ON g.user_id=u.id
    WHERE u."emailVerified"=true
      AND g.operator_reference='Owner authorized support access 2026-10-17';
  INSERT INTO exp_member_community_reservation(handle,user_id) VALUES('tapps',owner_id)
    ON CONFLICT(handle) DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM exp_member_community_reservation WHERE handle='tapps' AND user_id=owner_id)
    THEN RAISE EXCEPTION 'Handle is bound to a different account; no change made'; END IF;
END;
$owner_handle$;
COMMIT;
