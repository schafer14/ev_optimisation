CREATE TABLE IF NOT EXISTS accounts (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS api_keys (
    hashed_key TEXT PRIMARY KEY,
    account_slug TEXT NOT NULL REFERENCES accounts(slug)
);

CREATE TABLE IF NOT EXISTS usage (
    account_slug TEXT PRIMARY KEY REFERENCES accounts(slug),
    count INTEGER NOT NULL DEFAULT 0,
    last_updated TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS requests (
    id TEXT PRIMARY KEY,
    account_slug TEXT NOT NULL REFERENCES accounts(slug),
    request_body TEXT NOT NULL,
    response_body TEXT,
    status INTEGER NOT NULL,
    solve_time_ms REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
