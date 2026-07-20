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
  };
}

export function validateRuleSet(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== "object") return false;
  const rules = value as Record<string, unknown>;
  if (!Number.isInteger(rules.revision) || typeof rules.timeZoneIdentifier !== "string") return false;
  if (!Array.isArray(rules.activityRules) || !Array.isArray(rules.overrides)) return false;
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
          && Number.isInteger(item.endMinute) && Number(item.endMinute) >= 0 && Number(item.endMinute) <= 1_440;
      });
  });
}
