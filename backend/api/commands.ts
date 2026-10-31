import { randomUUID } from "node:crypto";
import { database, rows } from "../src/db.js";
import { parseRemoteCommand, parseRemoteReport, remoteDeliveryDeadline } from "../src/domain.js";
import { authenticate, errorResponse, HttpError, json, nodeHandler, readJSON } from "../src/http.js";
import { mapCommand } from "../src/mappers.js";

async function create(request: Request): Promise<Response> {
  const credential = await authenticate(request, ["parent"]);
  const command = parseRemoteCommand(await readJSON(request));
  if (!command) throw new HttpError(400, "远程命令格式无效");
  const sql = database();
  const deviceRows = rows(await sql`SELECT id FROM devices
    WHERE household_id = ${credential.householdID} AND revoked_at IS NULL
    ORDER BY created_at DESC LIMIT 1`);
  const device = deviceRows[0];
  if (!device) throw new HttpError(409, "还没有配对孩子的 Mac");
  const deviceID = String(device.id);

  // A second press while the first is on its way answers with the first, so one press can never
  // turn into two notices on the child's screen.
  const openRows = rows(await sql`SELECT * FROM remote_commands
    WHERE household_id = ${credential.householdID} AND device_id = ${deviceID}
      AND kind = ${command.kind} AND target = ${command.target}
      AND ((status = 'pending' AND expires_at > now())
        OR (status = 'received' AND received_at > now() - interval '3 minutes'))
    ORDER BY created_at DESC LIMIT 1`);
  if (openRows[0]) return json({ command: mapCommand(openRows[0]) });

  const now = new Date();
  const created = rows(await sql`INSERT INTO remote_commands (
    id, household_id, device_id, kind, target, lock_option, status, created_at, expires_at
  ) VALUES (
    ${randomUUID()}, ${credential.householdID}, ${deviceID}, ${command.kind}, ${command.target},
    ${command.lock}, 'pending', ${now.toISOString()}, ${remoteDeliveryDeadline(command.kind, now).toISOString()}
  ) RETURNING *`);
  return json({ command: mapCommand(created[0]!) }, 201);
}

async function report(request: Request): Promise<Response> {
  const credential = await authenticate(request, ["child"]);
  if (!credential.deviceID) throw new HttpError(403, "孩子凭据没有关联设备");
  const body = parseRemoteReport(await readJSON(request));
  if (!body) throw new HttpError(400, "远程命令回报格式无效");
  const sql = database();
  const at = body.at.toISOString();
  if (body.status === "received") {
    await sql`UPDATE remote_commands SET status = 'received', received_at = ${at}
      WHERE id = ${body.id} AND household_id = ${credential.householdID}
        AND device_id = ${credential.deviceID} AND status = 'pending'`;
    return json({ ok: true });
  }
  await sql`UPDATE remote_commands SET
      status = 'finished',
      received_at = COALESCE(received_at, ${at}),
      finished_at = ${at},
      outcome = ${body.outcome},
      closed_apps = ${JSON.stringify(body.closedApps)}::jsonb,
      failed_apps = ${JSON.stringify(body.failedApps)}::jsonb,
      front_app_name = ${body.frontAppName},
      front_app_bundle_id = ${body.frontAppBundleID},
      lock_ends_at = ${body.lockEndsAt?.toISOString() ?? null}
    WHERE id = ${body.id} AND household_id = ${credential.householdID}
      AND device_id = ${credential.deviceID} AND status <> 'finished'`;
  return json({ ok: true });
}

// One function for both directions: the free Vercel plan has limited how many a deployment may hold.
async function handler(request: Request): Promise<Response> {
  try {
    if (request.method === "POST") return await create(request);
    if (request.method === "PATCH") return await report(request);
    throw new HttpError(405, "不支持的请求方法");
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
