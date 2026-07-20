CREATE TABLE IF NOT EXISTS households (
  id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS credentials (
  id uuid PRIMARY KEY,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('parent', 'child')),
  device_id uuid,
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE INDEX IF NOT EXISTS credentials_token_idx
  ON credentials(token_hash) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS devices (
  id uuid PRIMARY KEY,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE TABLE IF NOT EXISTS pairing_codes (
  id uuid PRIMARY KEY,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rules (
  household_id uuid PRIMARY KEY REFERENCES households(id) ON DELETE CASCADE,
  document jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device_status (
  device_id uuid PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  category text NOT NULL,
  last_seen_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS violation_events (
  id uuid PRIMARY KEY,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN ('game', 'video')),
  app_name text NOT NULL,
  normalized_domain text,
  started_at timestamptz NOT NULL,
  duration_seconds integer NOT NULL,
  warning_count integer NOT NULL,
  was_enforced boolean NOT NULL,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS events_household_started_idx
  ON violation_events(household_id, started_at DESC);

CREATE TABLE IF NOT EXISTS temporary_requests (
  id uuid PRIMARY KEY,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN ('game', 'video')),
  duration_minutes integer NOT NULL CHECK (duration_minutes IN (15, 30, 60)),
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'denied')),
  created_at timestamptz NOT NULL,
  resolved_at timestamptz
);

CREATE TABLE IF NOT EXISTS temporary_grants (
  id uuid PRIMARY KEY,
  request_id uuid NOT NULL UNIQUE REFERENCES temporary_requests(id) ON DELETE CASCADE,
  household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN ('game', 'video')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL
);
