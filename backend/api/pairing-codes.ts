import { randomUUID } from "node:crypto";
import { database } from "../src/db.js";
import { generatePairingCode, hashPairingCode } from "../src/domain.js";
import { asISO, authenticate, errorResponse, HttpError, json, nodeHandler, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "POST");
    const credential = await authenticate(request, ["parent"]);
    const secret = process.env.PAIRING_SECRET;
    if (!secret) throw new HttpError(500, "PAIRING_SECRET 未配置");
    const sql = database();
    await sql`DELETE FROM pairing_codes WHERE household_id = ${credential.householdID}`;
    const code = generatePairingCode();
    const expiresAt = new Date(Date.now() + 10 * 60_000);
    await sql`INSERT INTO pairing_codes (id, household_id, code_hash, expires_at)
      VALUES (${randomUUID()}, ${credential.householdID}, ${hashPairingCode(code, secret)}, ${expiresAt.toISOString()})`;
    return json({ code, expiresAt: asISO(expiresAt) }, 201);
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
