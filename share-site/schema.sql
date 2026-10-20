CREATE TABLE IF NOT EXISTS shared_songs (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT NOT NULL DEFAULT '',
  cover_base64 TEXT NOT NULL,
  cover_type TEXT NOT NULL,
  preview_base64 TEXT,
  preview_type TEXT,
  preview_width INTEGER NOT NULL DEFAULT 1200,
  preview_height INTEGER NOT NULL DEFAULT 630,
  deep_link TEXT NOT NULL,
  fallback_url TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_shared_songs_created_at
  ON shared_songs(created_at);

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
