import { database } from "../src/db.js";
import { isAllowedDuration, isRestrictedCategory } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "POST");
    const credential = await authenticate(request, ["child"]);
    if (!credential.deviceID) throw new HttpError(403, "孩子凭据没有关联设备");
    const body = await readJSON(request);
    if (typeof body.id !== "string" || !isRestrictedCategory(body.category)
      || !isAllowedDuration(body.durationMinutes) || typeof body.createdAt !== "string") {
      throw new HttpError(400, "临时申请格式无效");
    }
    const createdAt = new Date(body.createdAt);
    if (Number.isNaN(createdAt.getTime())) throw new HttpError(400, "申请时间无效");
    const sql = database();
    await sql`INSERT INTO temporary_requests (
      id, household_id, device_id, category, duration_minutes, status, created_at
    ) VALUES (
      ${body.id}, ${credential.householdID}, ${credential.deviceID}, ${body.category},
      ${body.durationMinutes}, 'pending', ${createdAt.toISOString()}
    ) ON CONFLICT (id) DO NOTHING`;
    return json({ ok: true }, 201);
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
