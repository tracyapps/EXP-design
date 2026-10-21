-- Operator only, after 010. No role creation, public grants or job-role changes.
GRANT SELECT,INSERT,UPDATE,DELETE ON exp_member_share_link, exp_member_share_event,
  exp_member_referral_credit, exp_member_feedback, exp_member_engagement_limit TO exp_account_app;
