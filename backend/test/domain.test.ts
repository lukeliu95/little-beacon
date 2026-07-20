import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultRules,
  generatePairingCode,
  generateToken,
  hashPairingCode,
  hashToken,
  isAllowedDuration,
  secureStringEqual,
  validateRuleSet,
} from "../src/domain.js";

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

test("starter rules pass validation and malformed windows do not", () => {
  const rules = defaultRules();
  assert.equal(validateRuleSet(rules), true);
  const malformed = structuredClone(rules);
  malformed.activityRules[0]!.windows[0]!.weekday = 9;
  assert.equal(validateRuleSet(malformed), false);
});
