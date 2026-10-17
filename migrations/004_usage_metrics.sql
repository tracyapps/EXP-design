-- Private first-party usage records. No account/email/content columns or joins.
CREATE TABLE IF NOT EXISTS exp_usage_events (
  install_id uuid NOT NULL,
  event_id uuid NOT NULL,
  consent_version text NOT NULL CHECK (consent_version = 'usage-v1'),
  event_name text NOT NULL CHECK (event_name IN ('eligible_first_run', 'work_started', 'work_edited', 'output_completed', 'activation_completed', 'active_day')),
  event_day date NOT NULL,
  app_version text NOT NULL CHECK (app_version ~ '^[0-9]{1,3}\.[0-9]{1,3}$'),
  os_major smallint NOT NULL CHECK (os_major BETWEEN 1 AND 99),
  source text CHECK (source IN ('new', 'opened', 'svg', 'image', 'pdf', 'xd', 'figma', 'html', 'codepen', 'storybook')),
  output text CHECK (output IN ('png', 'jpg', 'pdf', 'svg', 'batch', 'handoff', 'html', 'tokens', 'codepen_launcher')),
  received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (install_id, event_id)
);
CREATE INDEX IF NOT EXISTS exp_usage_events_retention ON exp_usage_events(received_at);
CREATE TABLE IF NOT EXISTS exp_usage_limits (
  install_id uuid NOT NULL,
  received_day date NOT NULL DEFAULT CURRENT_DATE,
  attempts integer NOT NULL,
  PRIMARY KEY (install_id, received_day)
);
-- Semantic milestone dedup survives retries/relaunch/replayed event UUIDs.
CREATE UNIQUE INDEX IF NOT EXISTS exp_usage_first_run ON exp_usage_events(install_id)
  WHERE event_name = 'eligible_first_run';
CREATE UNIQUE INDEX IF NOT EXISTS exp_usage_activation ON exp_usage_events(install_id)
  WHERE event_name = 'activation_completed';
CREATE UNIQUE INDEX IF NOT EXISTS exp_usage_active_day ON exp_usage_events(install_id, event_day)
  WHERE event_name = 'active_day';
REVOKE ALL ON exp_usage_events, exp_usage_limits FROM PUBLIC;
