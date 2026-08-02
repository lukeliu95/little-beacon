import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultRules,
  generatePairingCode,
  generateToken,
  hashPairingCode,
  hashToken,
  isAllowedDuration,
  mergeMissingRuleSettings,
  parseRequestStartsAt,
  secureStringEqual,
  shouldAcceptRuleRevision,
  validateRuleSet,
} from "../src/domain.js";
import { asISO } from "../src/http.js";

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
