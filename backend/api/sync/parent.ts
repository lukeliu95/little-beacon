import { cleanupExpired, database, rows } from "../../src/db.js";
import { authenticate, errorResponse, json, nodeHandler, requireMethod } from "../../src/http.js";
import { mapCommand, mapEvent, mapRequest, mapStatus } from "../../src/mappers.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "GET");
    const credential = await authenticate(request, ["parent"]);
    const sql = database();
    await cleanupExpired(sql);
    const [ruleResult, statusResult, eventResult, requestResult, commandResult] = await Promise.all([
      sql`SELECT document FROM rules WHERE household_id = ${credential.householdID} LIMIT 1`,
      sql`SELECT category, last_seen_at, daily_usage_seconds FROM device_status
        WHERE household_id = ${credential.householdID} ORDER BY last_seen_at DESC LIMIT 1`,
      sql`SELECT * FROM violation_events WHERE household_id = ${credential.householdID}
        ORDER BY started_at DESC LIMIT 500`,
      sql`SELECT * FROM temporary_requests WHERE household_id = ${credential.householdID}
        AND created_at > now() - interval '30 days' ORDER BY created_at DESC LIMIT 200`,
      sql`SELECT * FROM remote_commands WHERE household_id = ${credential.householdID}
        ORDER BY created_at DESC LIMIT 100`,
    ]);
    const ruleRows = rows(ruleResult);
    const statusRows = rows(statusResult);
    const eventRows = rows(eventResult);
    const requestRows = rows(requestResult);
    const commandRows = rows(commandResult);
    return json({
      status: mapStatus(statusRows[0]),
      events: eventRows.map(mapEvent),
      requests: requestRows.map(mapRequest),
      rules: ruleRows[0]?.document,
      commands: commandRows.map((row) => mapCommand(row)),
    });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
