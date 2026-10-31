import { remoteCommandStatus } from "./domain.js";
import { asISO } from "./http.js";

export function mapCommand(row: Record<string, unknown>, now = new Date()) {
  return {
    id: row.id,
    kind: row.kind,
    target: row.target,
    lock: row.lock_option,
    status: remoteCommandStatus(String(row.status), new Date(String(row.expires_at)), now),
    createdAt: asISO(row.created_at),
    expiresAt: asISO(row.expires_at),
    receivedAt: row.received_at ? asISO(row.received_at) : null,
    finishedAt: row.finished_at ? asISO(row.finished_at) : null,
    outcome: row.outcome ?? null,
    closedApps: row.closed_apps ?? [],
    failedApps: row.failed_apps ?? [],
    frontAppName: row.front_app_name ?? null,
    frontAppBundleID: row.front_app_bundle_id ?? null,
    lockEndsAt: row.lock_ends_at ? asISO(row.lock_ends_at) : null,
  };
}

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
    startsAt: row.starts_at ? asISO(row.starts_at) : null,
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
