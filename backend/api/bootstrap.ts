import { randomUUID } from "node:crypto";
import { database, ensureSchema, rows } from "../src/db.js";
import { defaultRules, generateToken, hashToken, secureStringEqual } from "../src/domain.js";
import { errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "POST");
    const body = await readJSON(request);
    const setupKey = process.env.SETUP_KEY;
    if (!setupKey || typeof body.setupKey !== "string" || !secureStringEqual(body.setupKey, setupKey)) {
      throw new HttpError(403, "部署密钥无效");
    }
    const sql = database();
    await ensureSchema(sql);
    const households = rows(await sql`SELECT id FROM households ORDER BY created_at ASC LIMIT 1`);
    let householdID: string;
    if (households.length === 0) {
      householdID = randomUUID();
      await sql`INSERT INTO households (id) VALUES (${householdID})`;
      await sql`INSERT INTO rules (household_id, document) VALUES (${householdID}, ${JSON.stringify(defaultRules())}::jsonb)`;
    } else {
      householdID = String(households[0]?.id);
    }

    await sql`UPDATE credentials SET revoked_at = now()
      WHERE household_id = ${householdID} AND role = 'parent' AND revoked_at IS NULL`;
    const token = generateToken();
    await sql`INSERT INTO credentials (id, household_id, role, token_hash)
      VALUES (${randomUUID()}, ${householdID}, 'parent', ${hashToken(token)})`;
    return json({ householdID, token }, 201);
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
