import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultRules,
  generatePairingCode,
  generateToken,
  hashPairingCode,
  hashToken,
  isAllowedDuration,
  isAllowedWarningCount,
  mergeMissingRuleSettings,
  parseRemoteCommand,
  parseRemoteReport,
  parseRequestStartsAt,
  remoteCommandStatus,
  remoteDeliveryDeadline,
  secureStringEqual,
  shouldAcceptRuleRevision,
  validateRuleSet,
} from "../src/domain.js";
import { asISO } from "../src/http.js";
import { mapCommand } from "../src/mappers.js";

const commandID = "6f9619ff-8b86-4d11-b42d-00c04fc964ff";

test("a record of the child's own extra time has no warnings and must be accepted", () => {
  assert.equal(isAllowedWarningCount(0), true);
  assert.equal(isAllowedWarningCount(3), true);
  assert.equal(isAllowedWarningCount(4), false);
  assert.equal(isAllowedWarningCount(-1), false);
  assert.equal(isAllowedWarningCount("0"), false);
});

test("a close must name its target and lock, an unlock never carries one", () => {
  assert.deepEqual(
    parseRemoteCommand({ kind: "close", target: "game", lock: "30m" }),
    { kind: "close", target: "game", lock: "30m" },
  );
  assert.deepEqual(
    parseRemoteCommand({ kind: "unlock", target: "browser", lock: "today" }),
    { kind: "unlock", target: "browser", lock: "none" },
  );
  assert.equal(parseRemoteCommand({ kind: "close", target: "game" }), null);
  assert.equal(parseRemoteCommand({ kind: "close", target: "video", lock: "none" }), null);
  assert.equal(parseRemoteCommand({ kind: "shutdown", target: "game", lock: "none" }), null);
});

test("a close stops being deliverable after five minutes, an unlock after a day", () => {
  const now = new Date("2026-10-31T12:00:00Z");
  assert.equal(remoteDeliveryDeadline("close", now).toISOString(), "2026-10-31T12:05:00.000Z");
  assert.equal(remoteDeliveryDeadline("unlock", now).toISOString(), "2026-11-01T12:00:00.000Z");
});

test("only an undelivered command expires", () => {
  const deadline = new Date("2026-10-31T12:05:00Z");
  const after = new Date("2026-10-31T12:05:00Z");
  const before = new Date("2026-10-31T12:04:59Z");
  assert.equal(remoteCommandStatus("pending", deadline, before), "pending");
  assert.equal(remoteCommandStatus("pending", deadline, after), "expired");
  assert.equal(remoteCommandStatus("received", deadline, after), "received");
  assert.equal(remoteCommandStatus("finished", deadline, after), "finished");
});

test("a report needs a real command id and a known outcome", () => {
  const at = "2026-10-31T12:00:00Z";
  assert.equal(parseRemoteReport({ id: "1; DROP TABLE", status: "received", at }), null);
  assert.equal(parseRemoteReport({ id: commandID, status: "done", at }), null);
  assert.equal(parseRemoteReport({ id: commandID, status: "finished", outcome: "exploded", at }), null);
  assert.equal(
    parseRemoteReport({ id: commandID, status: "finished", outcome: "closed", closedApps: "Roblox", at }),
    null,
  );
  assert.equal(
    parseRemoteReport({ id: commandID, status: "finished", outcome: "closed", lockEndsAt: "soon", at }),
    null,
  );
});

test("a report keeps what happened, bounded in size, and when it happened", () => {
  const now = new Date("2026-10-31T12:30:00Z");
  const report = parseRemoteReport({
    id: commandID,
    status: "finished",
    at: "2026-10-31T12:00:00Z",
    outcome: "partial",
    closedApps: Array.from({ length: 30 }, (_, index) => `Game ${index}`),
    failedApps: ["  Steam  ", "", 7],
    frontAppName: "x".repeat(500),
    frontAppBundleID: "com.example.game",
    lockEndsAt: "2026-10-31T12:30:00Z",
  }, now);
  assert.ok(report && report.status === "finished");
  assert.equal(report.at.toISOString(), "2026-10-31T12:00:00.000Z");
  assert.equal(report.closedApps.length, 20);
  assert.deepEqual(report.failedApps, ["Steam"]);
  assert.equal(report.frontAppName?.length, 200);
  assert.equal(report.lockEndsAt?.toISOString(), "2026-10-31T12:30:00.000Z");
});

test("a report dated in the future is not believed", () => {
  const now = new Date("2026-10-31T12:00:00Z");
  const report = parseRemoteReport({ id: commandID, status: "received", at: "2027-01-01T00:00:00Z" }, now);
  assert.equal(report?.at.getTime(), now.getTime());
});

test("the parent sees a pending command past its deadline as expired", () => {
  const row = {
    id: commandID,
    kind: "close",
    target: "browser",
    lock_option: "60m",
    status: "pending",
    created_at: "2026-10-31T12:00:00Z",
    expires_at: "2026-10-31T12:05:00Z",
  };
  const mapped = mapCommand(row, new Date("2026-10-31T12:06:00Z"));
  assert.equal(mapped.status, "expired");
  assert.equal(mapped.lock, "60m");
  assert.deepEqual(mapped.closedApps, []);
  assert.equal(mapped.lockEndsAt, null);
});

test("tokens are random, URL-safe, and only hashes are stable", () => {
  const first = generateToken();
  const second = generateToken();
  assert.notEqual(first, second);
  assert.match(first, /^[A-Za-z0-9_-]+$/);
  assert.equal(hashToken(first), hashToken(first));
  assert.notEqual(hashToken(first), first);
});

test("pairing codes are six digits and secret scoped", () => {
  const code = generatePairingCode();
  assert.match(code, /^\d{6}$/);
  assert.equal(hashPairingCode(code, "secret"), hashPairingCode(code, "secret"));
  assert.notEqual(hashPairingCode(code, "secret"), hashPairingCode(code, "other"));
});

test("constant-time equality rejects different values", () => {
  assert.equal(secureStringEqual("same", "same"), true);
  assert.equal(secureStringEqual("same", "different"), false);
});

test("temporary durations stay on the agreed presets", () => {
  assert.equal(isAllowedDuration(15), true);
  assert.equal(isAllowedDuration(30), true);
  assert.equal(isAllowedDuration(60), true);
  assert.equal(isAllowedDuration(999), false);
});

test("scheduled request start times accept valid ISO dates in the allowed window", () => {
  const now = new Date("2026-07-21T12:00:00Z");
  const parsed = parseRequestStartsAt("2026-07-22T16:00:00Z", now);
  assert.ok(parsed instanceof Date);
  assert.equal(parsed.toISOString(), "2026-07-22T16:00:00.000Z");
  // Slightly in the past (clock skew) is still fine, up to 24 hours.
  assert.ok(parseRequestStartsAt("2026-07-21T11:00:00Z", now) instanceof Date);
});

test("absent start times keep old clients working and mean start immediately", () => {
  assert.equal(parseRequestStartsAt(undefined), null);
  assert.equal(parseRequestStartsAt(null), null);
});

test("garbage or out-of-range start times are rejected", () => {
  const now = new Date("2026-07-21T12:00:00Z");
  assert.equal(parseRequestStartsAt("not-a-date", now), "invalid");
  assert.equal(parseRequestStartsAt(1_753_099_200_000, now), "invalid");
  assert.equal(parseRequestStartsAt("2026-08-04T12:00:01Z", now), "invalid"); // > 14 days ahead
  assert.equal(parseRequestStartsAt("2026-07-20T11:59:59Z", now), "invalid"); // > 24 hours past
});

test("starter rules pass validation and malformed windows do not", () => {
  const rules = defaultRules();
  assert.equal(rules.pomodoroMode, "gentle");
  assert.equal(validateRuleSet(rules), true);
  const malformed = structuredClone(rules);
  malformed.activityRules[0]!.windows[0]!.weekday = 9;
  assert.equal(validateRuleSet(malformed), false);
});

test("viewing-distance settings are bounded and malformed settings are rejected", () => {
  const rules = defaultRules();
  assert.equal(validateRuleSet(rules), true);

  const tooFrequent = structuredClone(rules);
  tooFrequent.viewingDistancePolicy.checkIntervalMinutes = 1;
  assert.equal(validateRuleSet(tooFrequent), false);

  const impossibleDistance = structuredClone(rules);
  impossibleDistance.viewingDistancePolicy.minimumDistanceCentimeters = 500;
  assert.equal(validateRuleSet(impossibleDistance), false);
});

test("older rule uploads preserve camera settings they do not understand", () => {
  const current = defaultRules();
  current.viewingDistancePolicy.enabled = true;
  const incoming = structuredClone(current) as Record<string, unknown>;
  delete incoming.viewingDistancePolicy;
  incoming.revision = 2;

  const merged = mergeMissingRuleSettings(incoming, current);
  assert.deepEqual(merged.viewingDistancePolicy, current.viewingDistancePolicy);
  assert.equal(merged.revision, 2);
});

test("older rule uploads preserve enforced pomodoro mode", () => {
  const current = defaultRules();
  current.pomodoroMode = "enforced";
  const incoming = structuredClone(current) as Record<string, unknown>;
  delete incoming.pomodoroMode;
  incoming.revision = 2;

  const merged = mergeMissingRuleSettings(incoming, current);
  assert.equal(merged.pomodoroMode, "enforced");
});

test("unknown pomodoro modes are rejected", () => {
  const rules = defaultRules();
  const malformed = structuredClone(rules) as Record<string, unknown>;
  malformed.pomodoroMode = "please-let-me-skip";

  assert.equal(validateRuleSet(malformed), false);
});

test("API dates use seconds precision for older Apple ISO-8601 decoders", () => {
  assert.equal(asISO(new Date("2026-07-20T12:34:56.123Z")), "2026-07-20T12:34:56Z");
});

test("stale rule uploads cannot replace a newer revision", () => {
  assert.equal(shouldAcceptRuleRevision(4, 3), false);
  assert.equal(shouldAcceptRuleRevision(4, 4), true);
  assert.equal(shouldAcceptRuleRevision(4, 5), true);
});

test("older rule uploads preserve the default reminder strategy", () => {
  const merged = mergeMissingRuleSettings({ revision: 3 }, { defaultReminderStrategy: "strict" });
  assert.equal(merged.defaultReminderStrategy, "strict");
});

test("unknown reminder strategies are rejected", () => {
  const rules = defaultRules();
  assert.equal(validateRuleSet(rules), true);
  assert.equal(validateRuleSet({ ...rules, defaultReminderStrategy: "severe" }), false);
});

test("a window may name its own reminder strategy", () => {
  const rules = defaultRules();
  const withStrategy = (reminderStrategy: unknown) => ({
    ...rules,
    activityRules: rules.activityRules.map((rule) => ({
      ...rule,
      windows: rule.windows.map((window) => ({ ...window, reminderStrategy })),
    })),
  });
  assert.equal(validateRuleSet(withStrategy("strict")), true);
  assert.equal(validateRuleSet(withStrategy(null)), true);
  assert.equal(validateRuleSet(withStrategy("severe")), false);
});
