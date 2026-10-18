-- Operator only, after migration 009 and creation of ordinary LOGIN roles.
-- Existing app grants are retained; no role creation/password/admin membership.
GRANT SELECT,INSERT,UPDATE,DELETE ON exp_member_ticket_preference TO exp_account_app;
GRANT SELECT,INSERT,DELETE ON exp_member_ticket_mail TO exp_account_app;

GRANT USAGE ON SCHEMA public TO exp_account_jobs;
GRANT SELECT(id,email,"emailVerified") ON exp_member_user TO exp_account_jobs;
GRANT SELECT(id,ticket_id) ON exp_member_ticket_event TO exp_account_jobs;
GRANT SELECT(user_id,email_alerts) ON exp_member_ticket_preference TO exp_account_jobs;
GRANT SELECT(user_id) ON exp_member_support_grant TO exp_account_jobs;
GRANT SELECT,UPDATE,DELETE ON exp_member_ticket_mail TO exp_account_jobs;

-- FOR UPDATE SKIP LOCKED needs UPDATE on at least one selected column. Limit
-- it to the primary key; this role cannot edit message text or grant staff access.
GRANT SELECT(id,status,updated_at,user_id),DELETE,UPDATE(id) ON exp_member_ticket TO exp_account_jobs;
GRANT SELECT(id,"expiresAt"),DELETE,UPDATE(id) ON exp_member_session TO exp_account_jobs;
GRANT SELECT(id,"expiresAt"),DELETE,UPDATE(id) ON exp_member_verification TO exp_account_jobs;
GRANT SELECT(id,"lastRequest"),DELETE,UPDATE(id) ON exp_member_rate_limit TO exp_account_jobs;
GRANT SELECT(key,sent_at),DELETE,UPDATE(key) ON exp_member_mail_limit TO exp_account_jobs;
GRANT SELECT(user_id,window_start),DELETE,UPDATE(user_id) ON exp_member_beta_limit TO exp_account_jobs;
GRANT SELECT(user_id,window_start),DELETE,UPDATE(user_id) ON exp_member_community_limit TO exp_account_jobs;
GRANT SELECT(user_id,window_start),DELETE,UPDATE(user_id) ON exp_member_ticket_limit TO exp_account_jobs;
GRANT SELECT(id,created_at),DELETE,UPDATE(id) ON exp_member_beta_feedback TO exp_account_jobs;
GRANT SELECT(id,resolved_at),DELETE,UPDATE(id) ON exp_member_community_report TO exp_account_jobs;
GRANT SELECT(id,created_at),DELETE,UPDATE(id) ON exp_member_support_audit TO exp_account_jobs;
