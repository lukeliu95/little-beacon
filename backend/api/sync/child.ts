import { cleanupExpired, database, rows } from "../../src/db.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, requireMethod } from "../../src/http.js";
import { mapCommand, mapGrant, mapRequest } from "../../src/mappers.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "GET");
    const credential = await authenticate(request, ["child"]);
    if (!credential.deviceID) throw new HttpError(403, "孩子凭据没有关联设备");
    const sql = database();
    await cleanupExpired(sql);
    const [ruleResult, grantResult, requestResult, commandResult] = await Promise.all([
      sql`SELECT document FROM rules WHERE household_id = ${credential.householdID} LIMIT 1`,
      sql`SELECT * FROM temporary_grants WHERE household_id = ${credential.householdID}
        AND device_id = ${credential.deviceID} AND ends_at > now() ORDER BY ends_at ASC`,
      sql`SELECT * FROM temporary_requests WHERE household_id = ${credential.householdID}
        AND device_id = ${credential.deviceID} AND created_at > now() - interval '30 days'
        ORDER BY created_at DESC LIMIT 200`,
      sql`SELECT * FROM remote_commands WHERE household_id = ${credential.householdID}
        AND device_id = ${credential.deviceID} AND status = 'pending' AND expires_at > now()
        ORDER BY created_at ASC LIMIT 20`,
    ]);
    const ruleRows = rows(ruleResult);
    const grantRows = rows(grantResult);
    const requestRows = rows(requestResult);
    const commandRows = rows(commandResult);
    return json({
      rules: ruleRows[0]?.document,
      grants: grantRows.map(mapGrant),
      requests: requestRows.map(mapRequest),
      commands: commandRows.map((row) => mapCommand(row)),
    });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
