// Pure helpers for the ingest route: request validation, the guest gate, image sniffing and key building.
// No imports on purpose: the unit tests load this file directly.

export type IngestRequest = {
  email: string; responseId: string; prompt: string; roomType: string; theme: string;
  space: string | null; resultUrls: string[]; referenceUrl: string | null;
};
export type Checked = { ok: true; value: IngestRequest } | { ok: false; status: number; code: string };

const REF = /^[A-Za-z0-9_.:-]{1,120}$/;
const bad = (code: string, status = 400): Checked => ({ ok: false, status, code });
const str = (v: unknown, min: number, max: number): string | null => {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return s.length >= min && s.length <= max ? s : null;
};

/** Exact host or a subdomain of an allowed host; https only, no credentials, no port. */
export function sourceUrlAllowed(raw: unknown, hosts: string[]): boolean {
  if (typeof raw !== "string" || raw.length > 2000) return false;
  let u: URL;
  try { u = new URL(raw); } catch { return false; }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return false;
  const h = u.hostname.toLowerCase();
  return hosts.some((a) => a && (h === a || h.endsWith("." + a)));
}

/** Guests are API runs with no signed-in user: Pickaxe sends API_GUEST:... as the identifier and an empty email. */
export function isGuest(identifier: unknown, email: unknown): boolean {
  if (typeof identifier === "string" && identifier.trim().toLowerCase().startsWith("api_guest:")) return true;
  return typeof email !== "string" || email.trim() === "";
}

export function check(body: unknown, hosts: string[]): Checked {
  if (!body || typeof body !== "object" || Array.isArray(body)) return bad("invalid_body");
  const b = body as Record<string, unknown>;
  if (isGuest(b.identifier, b.email)) return bad("guest", 403);
  const email = str(b.email, 3, 254)?.toLowerCase() ?? null;
  if (!email || !/^[^\s@]+@[^\s@]+$/.test(email)) return bad("invalid_email");
  const responseId = typeof b.response_id === "string" && REF.test(b.response_id) ? b.response_id : null;
  if (!responseId) return bad("invalid_response_id");
  const prompt = str(b.prompt, 1, 2000), roomType = str(b.room_type, 1, 100), theme = str(b.theme, 1, 100);
  if (!prompt || !roomType || !theme) return bad("invalid_fields");
  let space: string | null = null;
  if (b.space !== undefined && b.space !== null && b.space !== "") {
    space = str(b.space, 1, 200);
    if (!space) return bad("invalid_space");
  }
  const urls = b.result_urls;
  if (!Array.isArray(urls) || urls.length < 1 || urls.length > 8 || !urls.every((u) => sourceUrlAllowed(u, hosts))) return bad("invalid_result_urls");
  let referenceUrl: string | null = null;
  if (b.reference_url !== undefined && b.reference_url !== null && b.reference_url !== "") {
    if (!sourceUrlAllowed(b.reference_url, hosts)) return bad("invalid_reference_url");
    referenceUrl = b.reference_url as string;
  }
  return { ok: true, value: { email, responseId, prompt, roomType, theme, space, resultUrls: urls as string[], referenceUrl } };
}

export const MAX_IMAGE_BYTES = 12 * 1024 * 1024;

/** Decide the type from the bytes, never from the sender's header. */
export function sniffImage(b: Uint8Array): { ext: string; type: string } | null {
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return { ext: "png", type: "image/png" };
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { ext: "jpg", type: "image/jpeg" };
  if (b.length >= 12 && String.fromCharCode(...b.slice(0, 4)) === "RIFF" && String.fromCharCode(...b.slice(8, 12)) === "WEBP") return { ext: "webp", type: "image/webp" };
  return null;
}

/** Keys satisfy the database check (^[A-Za-z0-9_./-]{1,255}$): the response id is hashed in, never used raw. */
export function objectKey(kind: "designs" | "references", subject: string, refHash: string, index: number, ext: string): string {
  return `${kind}/${subject}/${refHash}/${index}.${ext}`;
}
