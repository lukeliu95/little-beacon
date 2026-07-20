import { database, rows } from "../src/db.js";
import { shouldAcceptRuleRevision, validateRuleSet } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "PUT");
    const credential = await authenticate(request, ["parent"]);
    const document: unknown = await request.json();
    if (!validateRuleSet(document)) throw new HttpError(400, "家庭规则格式无效");
    const sql = database();
    const incomingRevision = Number(document.revision);
    const currentRows = rows(await sql`SELECT document FROM rules
      WHERE household_id = ${credential.householdID} LIMIT 1`);
    const currentDocument = currentRows[0]?.document as Record<string, unknown> | undefined;
    const currentRevision = Number(currentDocument?.revision ?? 0);
    if (!shouldAcceptRuleRevision(currentRevision, incomingRevision)) {
      return json({ ok: true, revision: currentRevision });
    }
    await sql`INSERT INTO rules (household_id, document, updated_at)
      VALUES (${credential.householdID}, ${JSON.stringify(document)}::jsonb, now())
      ON CONFLICT (household_id) DO UPDATE
      SET document = EXCLUDED.document, updated_at = now()
      WHERE COALESCE((rules.document ->> 'revision')::integer, 0) <= ${incomingRevision}`;
    return json({ ok: true, revision: incomingRevision });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
