import { database, rows } from "../src/db.js";
import { errorResponse, json, nodeHandler, requireMethod } from "../src/http.js";

async function handler(request: Request): Promise<Response> {
  try {
    requireMethod(request, "GET");
    const sql = database();
    const result = rows(await sql`SELECT now() AS now`);
    return json({ ok: true, databaseTime: result[0]?.now });
  } catch (error) {
    return errorResponse(error);
  }
}

export default nodeHandler(handler);
