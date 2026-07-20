import { randomUUID } from "node:crypto";
import { database, rows } from "../src/db.js";
import { generateToken, hashPairingCode, hashToken, secureStringEqual } from "../src/domain.js";
import { errorResponse, HttpError, json, nodeHandler, readJSON, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "POST");
    const body = await readJSON(request);
    if (typeof body.code !== "string" || !/^\d{6}$/.test(body.code)) {
      throw new HttpError(400, "配对码必须是 6 位数字");
    }
    if (typeof body.deviceName !== "string" || body.deviceName.trim().length < 1 || body.deviceName.length > 100) {
      throw new HttpError(400, "设备名称无效");
    }
    const secret = process.env.PAIRING_SECRET;
    if (!secret) throw new HttpError(500, "PAIRING_SECRET 未配置");
    const sql = database();
    const result = rows(await sql`SELECT id, household_id, code_hash, attempts
      FROM pairing_codes
      WHERE used_at IS NULL AND expires_at > now()
      ORDER BY created_at DESC LIMIT 1`);
    const row = result[0];
    if (!row) throw new HttpError(410, "配对码已过期，请让家长重新生成");
    if (Number(row.attempts) >= 5) throw new HttpError(429, "尝试次数过多，请重新生成配对码");
    const suppliedHash = hashPairingCode(body.code, secret);
    if (!secureStringEqual(suppliedHash, String(row.code_hash))) {
      await sql`UPDATE pairing_codes SET attempts = attempts + 1 WHERE id = ${String(row.id)}`;
      throw new HttpError(403, "配对码不正确");
    }

    const householdID = String(row.household_id);
    const deviceID = randomUUID();
    const token = generateToken();
    await sql`UPDATE pairing_codes SET used_at = now() WHERE id = ${String(row.id)}`;
    await sql`UPDATE devices SET revoked_at = now()
      WHERE household_id = ${householdID} AND revoked_at IS NULL`;
    await sql`UPDATE credentials SET revoked_at = now()
      WHERE household_id = ${householdID} AND role = 'child' AND revoked_at IS NULL`;
    await sql`INSERT INTO devices (id, household_id, name)
      VALUES (${deviceID}, ${householdID}, ${body.deviceName.trim()})`;
    await sql`INSERT INTO credentials (id, household_id, role, device_id, token_hash)
      VALUES (${randomUUID()}, ${householdID}, 'child', ${deviceID}, ${hashToken(token)})`;
    return json({ householdID, deviceID, token }, 201);
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
