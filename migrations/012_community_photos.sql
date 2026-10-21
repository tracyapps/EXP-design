-- Apply after 007. Separate draft/public snapshots; never join private user.image publicly.
BEGIN;
ALTER TABLE exp_member_community
  ADD COLUMN draft_photo text CHECK (draft_photo IS NULL OR (length(draft_photo)<=90000 AND draft_photo ~ '^data:image/webp;base64,[A-Za-z0-9+/]+={0,2}$')),
  ADD COLUMN published_photo text CHECK (published_photo IS NULL OR (length(published_photo)<=90000 AND published_photo ~ '^data:image/webp;base64,[A-Za-z0-9+/]+={0,2}$')),
  ADD CONSTRAINT exp_community_photo_publication CHECK (published_at IS NOT NULL OR published_photo IS NULL);
COMMIT;
