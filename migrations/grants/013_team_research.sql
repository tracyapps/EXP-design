-- Operator only, after 013. Uses the existing private interest runtime role.
-- Substitute the actual least-privilege runtime role if named differently.
GRANT SELECT,INSERT,UPDATE,DELETE ON exp_team_research, exp_team_research_limit TO exp_interest_app;
