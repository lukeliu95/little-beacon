import { database } from "../src/db.js";
import { validateRuleSet } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "PUT");
    const credential = await authenticate(request, ["parent"]);
    const document: unknown = await request.json();
    if (!validateRuleSet(document)) throw new HttpError(400, "家庭规则格式无效");
    const sql = database();
    await sql`INSERT INTO rules (household_id, document, updated_at)
      VALUES (${credential.householdID}, ${JSON.stringify(document)}::jsonb, now())
      ON CONFLICT (household_id) DO UPDATE
      SET document = EXCLUDED.document, updated_at = now()`;
    return json({ ok: true });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
