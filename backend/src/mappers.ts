import { asISO } from "./http.js";

export function mapStatus(row: Record<string, unknown> | undefined) {
  if (!row) return null;
  const lastSeenAt = new Date(String(row.last_seen_at));
  return {
    category: row.category,
    lastSeenAt: lastSeenAt.toISOString(),
    isOnline: Date.now() - lastSeenAt.getTime() <= 90_000,
    dailyUsageSeconds: Number(row.daily_usage_seconds ?? 0),
  };
}

export function mapEvent(row: Record<string, unknown>) {
  return {
    id: row.id,
    category: row.category,
    appName: row.app_name,
    normalizedDomain: row.normalized_domain,
    startedAt: asISO(row.started_at),
    durationSeconds: Number(row.duration_seconds),
    warningCount: Number(row.warning_count),
    wasEnforced: Boolean(row.was_enforced),
    expiresAt: asISO(row.expires_at),
  };
}

export function mapRequest(row: Record<string, unknown>) {
  return {
    id: row.id,
    category: row.category,
    durationMinutes: Number(row.duration_minutes),
    status: row.status,
    createdAt: asISO(row.created_at),
    resolvedAt: row.resolved_at ? asISO(row.resolved_at) : null,
  };
}

export function mapGrant(row: Record<string, unknown>) {
  return {
    id: row.id,
    category: row.category,
    startsAt: asISO(row.starts_at),
    endsAt: asISO(row.ends_at),
  };
}
