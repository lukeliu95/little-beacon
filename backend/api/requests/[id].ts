import { randomUUID } from "node:crypto";
import { database, rows } from "../../src/db.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../../src/http.js";
import { mapGrant } from "../../src/mappers.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "PATCH");
    const credential = await authenticate(request, ["parent"]);
    const id = new URL(request.url).pathname.split("/").filter(Boolean).at(-1);
    if (!id) throw new HttpError(400, "缺少申请 ID");
    const body = await readJSON(request);
    if (typeof body.approved !== "boolean") throw new HttpError(400, "审批结果无效");
    const sql = database();
    const requests = rows(await sql`SELECT * FROM temporary_requests
      WHERE id = ${id} AND household_id = ${credential.householdID} LIMIT 1`);
    const item = requests[0];
    if (!item) throw new HttpError(404, "找不到临时申请");
    if (item.status !== "pending") throw new HttpError(409, "这个申请已经处理过了");
    const status = body.approved ? "approved" : "denied";
    await sql`UPDATE temporary_requests SET status = ${status}, resolved_at = now()
      WHERE id = ${id} AND household_id = ${credential.householdID}`;
    if (!body.approved) return json({ grant: null });

    const grantID = randomUUID();
    // A scheduled request grants its requested window (even if it has already passed —
    // the parent saw the window when approving); an immediate one starts now.
    const startsAt = item.starts_at ? new Date(String(item.starts_at)) : new Date();
    const endsAt = new Date(startsAt.getTime() + Number(item.duration_minutes) * 60_000);
    const grants = rows(await sql`INSERT INTO temporary_grants (
      id, request_id, household_id, device_id, category, starts_at, ends_at
    ) VALUES (
      ${grantID}, ${id}, ${credential.householdID}, ${String(item.device_id)}, ${String(item.category)},
      ${startsAt.toISOString()}, ${endsAt.toISOString()}
    ) RETURNING *`);
    return json({ grant: mapGrant(grants[0]!) });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
