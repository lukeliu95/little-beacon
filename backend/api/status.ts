import { database } from "../src/db.js";
import { isCategory } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "PUT");
    const credential = await authenticate(request, ["child"]);
    if (!credential.deviceID) throw new HttpError(403, "孩子凭据没有关联设备");
    const body = await readJSON(request);
    if (!isCategory(body.category) || typeof body.lastSeenAt !== "string") {
      throw new HttpError(400, "当前状态格式无效");
    }
    const seenAt = new Date(body.lastSeenAt);
    if (Number.isNaN(seenAt.getTime())) throw new HttpError(400, "同步时间无效");
    const sql = database();
    await sql`INSERT INTO device_status (device_id, household_id, category, last_seen_at)
      VALUES (${credential.deviceID}, ${credential.householdID}, ${body.category}, ${seenAt.toISOString()})
      ON CONFLICT (device_id) DO UPDATE
      SET category = EXCLUDED.category, last_seen_at = EXCLUDED.last_seen_at`;
    return json({ ok: true });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
