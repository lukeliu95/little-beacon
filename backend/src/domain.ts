import { createHash, createHmac, randomBytes, randomInt, randomUUID, timingSafeEqual } from "node:crypto";

export const categories = ["game", "video", "other", "idle"] as const;
export type ActivityCategory = (typeof categories)[number];
export type CredentialRole = "parent" | "child";

export function generateToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function generatePairingCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

export function hashPairingCode(code: string, secret: string): string {
  return createHmac("sha256", secret).update(code).digest("hex");
}

export function secureStringEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

export function isCategory(value: unknown): value is ActivityCategory {
  return typeof value === "string" && categories.includes(value as ActivityCategory);
}

export function isRestrictedCategory(value: unknown): value is "game" | "video" {
  return value === "game" || value === "video";
}

export function isAllowedDuration(value: unknown): value is 15 | 30 | 60 {
  return value === 15 || value === 30 || value === 60;
}

/** A child's own "再玩 5 分钟" is stored as an event with no warnings, so zero is valid. */
export function isAllowedWarningCount(value: unknown): boolean {
  return Number.isInteger(value) && Number(value) >= 0 && Number(value) <= 3;
}

const maxStartsAtAheadMs = 14 * 24 * 60 * 60 * 1_000;
const maxStartsAtBehindMs = 24 * 60 * 60 * 1_000;

/**
 * Parses the optional scheduled start of a temporary request. Absent (undefined/null)
 * means "start immediately" — 0.3.x clients never send the field — and maps to null.
 * A present value must be a valid ISO date string no more than 14 days ahead and no
 * more than 24 hours in the past; anything else is "invalid".
 */
export function parseRequestStartsAt(value: unknown, now = new Date()): Date | null | "invalid" {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return "invalid";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "invalid";
  if (date.getTime() - now.getTime() > maxStartsAtAheadMs) return "invalid";
  if (now.getTime() - date.getTime() > maxStartsAtBehindMs) return "invalid";
  return date;
}

export function shouldAcceptRuleRevision(currentRevision: number, incomingRevision: number): boolean {
  return Number.isInteger(incomingRevision) && incomingRevision >= currentRevision;
}

export function defaultRules() {
  const windows = (days: number[], startMinute: number, endMinute: number) =>
    days.map((weekday) => ({ id: randomUUID(), weekday, startMinute, endMinute }));
  return {
    revision: 1,
    timeZoneIdentifier: "Asia/Tokyo",
    activityRules: [
      {
        category: "game",
        windows: [
          ...windows([2, 3, 4, 5, 6], 18 * 60, 20 * 60),
          ...windows([1, 7], 14 * 60, 18 * 60),
        ],
      },
      {
        category: "video",
        windows: [
          ...windows([2, 3, 4, 5, 6], 18 * 60, 21 * 60),
          ...windows([1, 7], 10 * 60, 21 * 60),
        ],
      },
    ],
    overrides: [],
    // 25-minute eye-care break reminder, on by default; and a soft (notify-only) daily-usage
    // nudge threshold. Both are independent of the game/video rule engine above.
    pomodoroEnabled: true,
    pomodoroMode: "gentle",
    dailyUsageThresholdSeconds: 7_200,
    viewingDistancePolicy: {
      enabled: false,
      checkIntervalMinutes: 10,
      minimumDistanceCentimeters: 45,
    },
    defaultReminderStrategy: "standard",
  };
}

const optionalRuleSettingKeys = [
  "pomodoroEnabled",
  "pomodoroMode",
  "dailyUsageThresholdSeconds",
  "viewingDistancePolicy",
  "defaultReminderStrategy",
] as const;

const reminderStrategies = ["gentle", "standard", "strict"];

/**
 * Older clients do not know newer optional rule settings. Preserve those settings when an
 * otherwise newer whole-document upload omits them, instead of silently disabling a feature
 * that another device configured.
 */
export function mergeMissingRuleSettings(
  incoming: Record<string, unknown>,
  current: Record<string, unknown> | undefined,
): Record<string, unknown> {
  const merged = { ...incoming };
  if (!current) return merged;
  for (const key of optionalRuleSettingKeys) {
    if (merged[key] === undefined && current[key] !== undefined) {
      merged[key] = current[key];
    }
  }
  return merged;
}

export function validateRuleSet(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== "object") return false;
  const rules = value as Record<string, unknown>;
  if (!Number.isInteger(rules.revision) || typeof rules.timeZoneIdentifier !== "string") return false;
  if (!Array.isArray(rules.activityRules) || !Array.isArray(rules.overrides)) return false;
  // Both fields are optional for backward compatibility with documents saved before they
  // existed; when present, they must have the right shape.
  if (rules.pomodoroEnabled !== undefined && typeof rules.pomodoroEnabled !== "boolean") return false;
  if (
    rules.pomodoroMode !== undefined
    && !["off", "gentle", "enforced"].includes(String(rules.pomodoroMode))
  ) {
    return false;
  }
  if (
    rules.defaultReminderStrategy !== undefined
    && !reminderStrategies.includes(String(rules.defaultReminderStrategy))
  ) {
    return false;
  }
  if (
    rules.dailyUsageThresholdSeconds !== undefined
    && rules.dailyUsageThresholdSeconds !== null
    && !(Number.isInteger(rules.dailyUsageThresholdSeconds) && Number(rules.dailyUsageThresholdSeconds) >= 0)
  ) {
    return false;
  }
  if (rules.viewingDistancePolicy !== undefined) {
    if (
      !rules.viewingDistancePolicy
      || typeof rules.viewingDistancePolicy !== "object"
      || Array.isArray(rules.viewingDistancePolicy)
    ) {
      return false;
    }
    const policy = rules.viewingDistancePolicy as Record<string, unknown>;
    if (typeof policy.enabled !== "boolean") return false;
    if (
      !Number.isInteger(policy.checkIntervalMinutes)
      || Number(policy.checkIntervalMinutes) < 5
      || Number(policy.checkIntervalMinutes) > 60
    ) {
      return false;
    }
    if (
      !Number.isInteger(policy.minimumDistanceCentimeters)
      || Number(policy.minimumDistanceCentimeters) < 30
      || Number(policy.minimumDistanceCentimeters) > 80
    ) {
      return false;
    }
  }
  return rules.activityRules.every((rule) => {
    if (!rule || typeof rule !== "object") return false;
    const candidate = rule as Record<string, unknown>;
    return isRestrictedCategory(candidate.category) && Array.isArray(candidate.windows)
      && candidate.windows.every((window) => {
        if (!window || typeof window !== "object") return false;
        const item = window as Record<string, unknown>;
        return typeof item.id === "string"
          && Number.isInteger(item.weekday) && Number(item.weekday) >= 1 && Number(item.weekday) <= 7
          && Number.isInteger(item.startMinute) && Number(item.startMinute) >= 0 && Number(item.startMinute) < 1_440
          && Number.isInteger(item.endMinute) && Number(item.endMinute) >= 0 && Number(item.endMinute) <= 1_440
          && (item.reminderStrategy === undefined || item.reminderStrategy === null
            || reminderStrategies.includes(String(item.reminderStrategy)));
      });
  });
}

const remoteKinds = ["close", "unlock"] as const;
const remoteTargets = ["game", "browser"] as const;
const remoteLocks = ["none", "30m", "60m", "today"] as const;
const remoteOutcomes = ["closed", "partial", "nothingOpen", "closedByChild", "notConfirmed", "stale", "unlocked"] as const;
const remoteReportedApps = 20;
const remoteNameLength = 200;
const maxRemoteReportAheadMs = 5 * 60 * 1_000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type RemoteCommandInput = {
  kind: (typeof remoteKinds)[number];
  target: (typeof remoteTargets)[number];
  lock: (typeof remoteLocks)[number];
};

export type RemoteReport =
  | { id: string; status: "received"; at: Date }
  | {
    id: string;
    status: "finished";
    at: Date;
    outcome: (typeof remoteOutcomes)[number];
    closedApps: string[];
    failedApps: string[];
    frontAppName: string | null;
    frontAppBundleID: string | null;
    lockEndsAt: Date | null;
  };

function includes<T extends string>(list: readonly T[], value: unknown): value is T {
  return typeof value === "string" && list.includes(value as T);
}

/** An unlock never carries a lock; a close must say which one it wants. */
export function parseRemoteCommand(body: Record<string, unknown>): RemoteCommandInput | null {
  if (!includes(remoteKinds, body.kind) || !includes(remoteTargets, body.target)) return null;
  if (body.kind === "unlock") return { kind: "unlock", target: body.target, lock: "none" };
  return includes(remoteLocks, body.lock) ? { kind: "close", target: body.target, lock: body.lock } : null;
}

/**
 * A close nobody picked up within five minutes is dropped, so a Mac that wakes the next day does
 * not shut anything. An unlock only ever gives time back, so it waits for the Mac to return.
 */
export function remoteDeliveryDeadline(kind: RemoteCommandInput["kind"], now = new Date()): Date {
  const windowMs = kind === "close" ? 5 * 60 * 1_000 : 24 * 60 * 60 * 1_000;
  return new Date(now.getTime() + windowMs);
}

/** "expired" is never stored: a pending command simply stops being deliverable at its deadline. */
export function remoteCommandStatus(status: string, expiresAt: Date, now = new Date()): string {
  return status === "pending" && expiresAt.getTime() <= now.getTime() ? "expired" : status;
}

function remoteName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, remoteNameLength) : null;
}

function remoteNames(value: unknown): string[] | null {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) return null;
  return value.flatMap((item) => remoteName(item) ?? []).slice(0, remoteReportedApps);
}

function remoteDate(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * What the child Mac says about a command. `at` is its own clock, so a report held back by a
 * lost connection keeps the moment it happened; a time from the future falls back to now.
 */
export function parseRemoteReport(body: Record<string, unknown>, now = new Date()): RemoteReport | null {
  if (typeof body.id !== "string" || !uuidPattern.test(body.id)) return null;
  const reported = remoteDate(body.at);
  const at = reported && reported.getTime() - now.getTime() <= maxRemoteReportAheadMs ? reported : now;
  if (body.status === "received") return { id: body.id, status: "received", at };
  if (body.status !== "finished" || !includes(remoteOutcomes, body.outcome)) return null;
  const closedApps = remoteNames(body.closedApps);
  const failedApps = remoteNames(body.failedApps);
  if (!closedApps || !failedApps) return null;
  const lockEndsAt = body.lockEndsAt === undefined || body.lockEndsAt === null ? null : remoteDate(body.lockEndsAt);
  if ((body.lockEndsAt ?? null) !== null && !lockEndsAt) return null;
  return {
    id: body.id,
    status: "finished",
    at,
    outcome: body.outcome,
    closedApps,
    failedApps,
    frontAppName: remoteName(body.frontAppName),
    frontAppBundleID: remoteName(body.frontAppBundleID),
    lockEndsAt,
  };
}
