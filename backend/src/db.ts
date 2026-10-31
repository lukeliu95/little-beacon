import { neon } from "@neondatabase/serverless";

export type SQL = ReturnType<typeof neon>;
export type DBRow = Record<string, unknown>;

let client: SQL | undefined;

export function database(): SQL {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not configured");
  client ??= neon(url);
  return client;
}

export function rows(result: unknown): DBRow[] {
  return result as DBRow[];
}

export async function ensureSchema(sql: SQL): Promise<void> {
  await sql`CREATE TABLE IF NOT EXISTS households (
    id uuid PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now()
  )`;
  await sql`CREATE TABLE IF NOT EXISTS credentials (
    id uuid PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('parent', 'child')),
    device_id uuid,
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz
  )`;
  await sql`CREATE INDEX IF NOT EXISTS credentials_token_idx ON credentials(token_hash) WHERE revoked_at IS NULL`;
  await sql`CREATE TABLE IF NOT EXISTS devices (
    id uuid PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz
  )`;
  await sql`CREATE TABLE IF NOT EXISTS pairing_codes (
    id uuid PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    code_hash text NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
  )`;
  await sql`CREATE TABLE IF NOT EXISTS rules (
    household_id uuid PRIMARY KEY REFERENCES households(id) ON DELETE CASCADE,
    document jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
  )`;
  await sql`CREATE TABLE IF NOT EXISTS device_status (
    device_id uuid PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    category text NOT NULL,
    last_seen_at timestamptz NOT NULL
  )`;
  await sql`CREATE TABLE IF NOT EXISTS violation_events (
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
  )`;
  await sql`CREATE INDEX IF NOT EXISTS events_household_started_idx ON violation_events(household_id, started_at DESC)`;
  await sql`CREATE TABLE IF NOT EXISTS temporary_requests (
    id uuid PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    category text NOT NULL CHECK (category IN ('game', 'video')),
    duration_minutes integer NOT NULL CHECK (duration_minutes IN (15, 30, 60)),
    status text NOT NULL CHECK (status IN ('pending', 'approved', 'denied')),
    created_at timestamptz NOT NULL,
    resolved_at timestamptz
  )`;
  await sql`CREATE TABLE IF NOT EXISTS temporary_grants (
    id uuid PRIMARY KEY,
    request_id uuid NOT NULL UNIQUE REFERENCES temporary_requests(id) ON DELETE CASCADE,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    category text NOT NULL CHECK (category IN ('game', 'video')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL
  )`;
  await sql`CREATE TABLE IF NOT EXISTS remote_commands (
    id uuid PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('close', 'unlock')),
    target text NOT NULL CHECK (target IN ('game', 'browser')),
    lock_option text NOT NULL CHECK (lock_option IN ('none', '30m', '60m', 'today')),
    status text NOT NULL CHECK (status IN ('pending', 'received', 'finished')),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    received_at timestamptz,
    finished_at timestamptz,
    outcome text CHECK (outcome IN ('closed', 'partial', 'nothingOpen', 'closedByChild', 'notConfirmed', 'stale', 'unlocked')),
    closed_apps jsonb NOT NULL DEFAULT '[]',
    failed_apps jsonb NOT NULL DEFAULT '[]',
    front_app_name text,
    front_app_bundle_id text,
    lock_ends_at timestamptz
  )`;
  await sql`CREATE INDEX IF NOT EXISTS remote_commands_device_idx ON remote_commands(device_id, status, created_at)`;
}

export async function cleanupExpired(sql: SQL): Promise<void> {
  await sql`DELETE FROM violation_events WHERE expires_at <= now()`;
  await sql`DELETE FROM pairing_codes WHERE expires_at <= now() OR used_at IS NOT NULL`;
  await sql`DELETE FROM temporary_grants WHERE ends_at <= now()`;
  await sql`DELETE FROM remote_commands WHERE created_at <= now() - interval '30 days'`;
}
