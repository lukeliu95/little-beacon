import type { CredentialRole } from "./domain.js";
import { database, rows } from "./db.js";
import { hashToken } from "./domain.js";

export type Credential = {
  id: string;
  householdID: string;
  role: CredentialRole;
  deviceID: string | null;
};

type VercelRequest = {
  method?: string;
  url?: string;
  headers: Record<string, string | string[] | undefined>;
  body?: unknown;
};

type VercelResponse = {
  statusCode: number;
  setHeader(name: string, value: string): void;
  end(body?: Uint8Array | string): void;
};

function firstHeader(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function webRequest(request: VercelRequest): Request {
  const method = request.method ?? "GET";
  const headers = new Headers();
  for (const [name, value] of Object.entries(request.headers)) {
    if (Array.isArray(value)) value.forEach((item) => headers.append(name, item));
    else if (value !== undefined) headers.set(name, value);
  }

  const protocol = firstHeader(request.headers["x-forwarded-proto"]) ?? "https";
  const host = firstHeader(request.headers["x-forwarded-host"] ?? request.headers.host) ?? "localhost";
  const url = new URL(request.url ?? "/", `${protocol}://${host}`);
  let body: string | undefined;
  if (method !== "GET" && method !== "HEAD" && request.body !== undefined) {
    if (typeof request.body === "string") body = request.body;
    else if (request.body instanceof Uint8Array) body = Buffer.from(request.body).toString("utf8");
    else {
      body = JSON.stringify(request.body);
      if (!headers.has("content-type")) headers.set("content-type", "application/json");
    }
  }
  return new Request(url, { method, headers, body });
}

export function nodeHandler(
  handler: (request: Request) => Promise<Response>,
): (request: VercelRequest, response: VercelResponse) => Promise<void> {
  return async (request, response) => {
    const result = await handler(webRequest(request));
    response.statusCode = result.status;
    result.headers.forEach((value, name) => response.setHeader(name, value));
    response.end(new Uint8Array(await result.arrayBuffer()));
  };
}

export function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) return json({ error: error.message }, error.status);
  console.error(error);
  return json({ error: "服务器暂时无法完成请求" }, 500);
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export async function readJSON(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "请求 JSON 无效");
  }
}

export async function authenticate(request: Request, allowed: CredentialRole[]): Promise<Credential> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) throw new HttpError(401, "缺少设备凭据");
  const token = header.slice(7).trim();
  if (!token) throw new HttpError(401, "设备凭据无效");
  const sql = database();
  const result = rows(await sql`
    SELECT id, household_id, role, device_id
    FROM credentials
    WHERE token_hash = ${hashToken(token)} AND revoked_at IS NULL
    LIMIT 1
  `);
  const row = result[0];
  if (!row || !allowed.includes(row.role as CredentialRole)) throw new HttpError(403, "权限不足");
  return {
    id: String(row.id),
    householdID: String(row.household_id),
    role: row.role as CredentialRole,
    deviceID: row.device_id ? String(row.device_id) : null,
  };
}

export function requireMethod(request: Request, method: string): void {
  if (request.method !== method) throw new HttpError(405, "不支持的请求方法");
}

export function asISO(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  return new Date(String(value)).toISOString();
}
