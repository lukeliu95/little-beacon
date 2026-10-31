import { database } from "../src/db.js";
import { isAllowedWarningCount, isRestrictedCategory } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "POST");
    const credential = await authenticate(request, ["child"]);
    if (!credential.deviceID) throw new HttpError(403, "孩子凭据没有关联设备");
    const body = await readJSON(request);
    if (typeof body.id !== "string" || !isRestrictedCategory(body.category)
      || typeof body.appName !== "string" || body.appName.length > 200
      || !Number.isInteger(body.durationSeconds) || Number(body.durationSeconds) < 0
      || !isAllowedWarningCount(body.warningCount)
      || typeof body.wasEnforced !== "boolean" || typeof body.startedAt !== "string") {
      throw new HttpError(400, "违规事件格式无效");
    }
    if (body.normalizedDomain != null
      && (typeof body.normalizedDomain !== "string" || body.normalizedDomain.length > 253
        || body.normalizedDomain.includes("/") || body.normalizedDomain.includes(":"))) {
      throw new HttpError(400, "事件域名必须是规范化主机名");
    }
    const startedAt = new Date(body.startedAt);
    if (Number.isNaN(startedAt.getTime())) throw new HttpError(400, "事件时间无效");
    const expiresAt = new Date(startedAt.getTime() + 30 * 86_400_000);
    const sql = database();
    await sql`INSERT INTO violation_events (
      id, household_id, device_id, category, app_name, normalized_domain,
      started_at, duration_seconds, warning_count, was_enforced, expires_at
    ) VALUES (
      ${body.id}, ${credential.householdID}, ${credential.deviceID}, ${body.category},
      ${body.appName}, ${body.normalizedDomain ?? null}, ${startedAt.toISOString()},
      ${Number(body.durationSeconds)}, ${Number(body.warningCount)}, ${body.wasEnforced}, ${expiresAt.toISOString()}
    ) ON CONFLICT (id) DO UPDATE SET
      category = EXCLUDED.category,
      app_name = EXCLUDED.app_name,
      normalized_domain = EXCLUDED.normalized_domain,
      duration_seconds = EXCLUDED.duration_seconds,
      warning_count = EXCLUDED.warning_count,
      was_enforced = EXCLUDED.was_enforced,
      updated_at = now()
    WHERE violation_events.household_id = ${credential.householdID}
      AND violation_events.device_id = ${credential.deviceID}`;
    return json({ ok: true });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
