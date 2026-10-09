CREATE TABLE IF NOT EXISTS shared_playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  song_count INTEGER NOT NULL,
  payload TEXT NOT NULL,
  preview_base64 TEXT NOT NULL,
  preview_type TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_shared_playlists_created_at
  ON shared_playlists(created_at);
