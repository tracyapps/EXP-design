-- Separate, fresh mailbox confirmation for deleting only the live Pro-interest row.
BEGIN;
ALTER TABLE exp_pro_interest
  ADD COLUMN erasure_hash text UNIQUE CHECK (erasure_hash IS NULL OR erasure_hash ~ '^[a-f0-9]{64}$'),
  ADD COLUMN erasure_expires_at timestamptz,
  ADD COLUMN erasure_retry_after timestamptz;
COMMIT;
