// POST /api/interior-designs/ingest — records a finished design made outside the app (a Pickaxe agent) for a signed-in Pickaxe user.
// Installed by `rapscalyon.py pack add --app app` from the pack's server/ folder.
//
// Caller: a custom Python Pickaxe action. The email and identifier come from Pickaxe's runtime environment (not from model text).
// Auth: shared secret in x-ingest-secret (env IDG_INGEST_SECRET), constant time. Use HTTPS.
// Body: { identifier, email, response_id, prompt, room_type, theme, space?, result_urls[1..8], reference_url? }
// Flow: guest gate -> email must resolve to a confirmed account (never created here) -> the user's space (created on first use)
//       -> copy images into our storage (result URLs expire after 2 hours) -> idg_record_design (idempotent on response_id).
// Credits: none touched. Pickaxe credits are the ledger for this path.
import { createHash, timingSafeEqual } from "node:crypto";
import { supabaseService } from "@/lib/supabase/service";
import { check, MAX_IMAGE_BYTES, objectKey, sniffImage } from "./lib";
import { putObject, r2FromEnv } from "./r2";

const eq = (a: string, b: string) => {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};
const fail = (status: number, code: string, message?: string) => Response.json({ error: code, ...(message ? { message } : {}) }, { status });

/** Download with a size cap, no redirects, and a timeout. */
async function download(url: string): Promise<Uint8Array> {
  const res = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(20000) });
  if (!res.ok || !res.body) throw new Error(`source HTTP ${res.status}`);
  const declared = Number(res.headers.get("content-length") ?? 0);
  if (declared > MAX_IMAGE_BYTES) throw new Error("source too large");
  const chunks: Uint8Array[] = []; let total = 0;
  const reader = res.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > MAX_IMAGE_BYTES) { await reader.cancel(); throw new Error("source too large"); }
    chunks.push(value);
  }
  const out = new Uint8Array(total); let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

export async function POST(req: Request) {
  const secret = process.env.IDG_INGEST_SECRET, r2 = r2FromEnv();
  if (!secret || !r2) return fail(500, "not_configured");
  const given = req.headers.get("x-ingest-secret");
  if (!given || !eq(given, secret)) return fail(401, "unauthorized");

  const body = await req.json().catch(() => null);
  const hosts = (process.env.IDG_SOURCE_HOSTS ?? "cdn.mail.studio").split(",").map((h) => h.trim().toLowerCase()).filter(Boolean);
  const c = check(body, hosts);
  if (!c.ok) return fail(c.status, c.code);
  const r = c.value;

  const db = supabaseService();
  const { data: userId, error: uErr } = await db.rpc("idg_resolve_user", { p_email: r.email });
  if (uErr) { console.error("idg_resolve_user failed", uErr.code); return fail(500, "internal"); }
  if (!userId) return fail(404, "no_account", "No confirmed account for this email. Register and confirm your email first.");

  const { data: subjectId, error: sErr } = await db.rpc("idg_ensure_subject", { p_user: userId, p_name: r.space });
  if (sErr) {
    if (sErr.code === "53400") return fail(409, "space_limit", "Your plan does not allow another space.");
    console.error("idg_ensure_subject failed", sErr.code); return fail(500, "internal");
  }

  const ref = `pickaxe:${r.responseId}`;
  const refHash = createHash("sha256").update(ref).digest("hex").slice(0, 16);
  const copy = async (url: string, kind: "designs" | "references", i: number) => {
    let bytes: Uint8Array;
    try { bytes = await download(url); } catch (e) { throw Object.assign(new Error("source"), { code: "source_unavailable" }); }
    const img = sniffImage(bytes);
    if (!img) throw Object.assign(new Error("type"), { code: "not_an_image" });
    const key = objectKey(kind, String(subjectId), refHash, i, img.ext);
    try { await putObject(r2, key, bytes, img.type); } catch (e) { console.error("storage failed"); throw Object.assign(new Error("storage"), { code: "storage_failed" }); }
    return key;
  };

  let imageKeys: string[]; let refKey: string | null = null;
  try {
    imageKeys = await Promise.all(r.resultUrls.map((u, i) => copy(u, "designs", i)));
    if (r.referenceUrl) refKey = await copy(r.referenceUrl, "references", 0);
  } catch (e) {
    const code = (e as { code?: string }).code ?? "internal";
    if (code === "source_unavailable") return fail(502, code, "The image link could not be fetched; result links expire after 2 hours.");
    if (code === "not_an_image") return fail(422, code);
    return fail(500, code === "storage_failed" ? code : "internal");
  }

  const { data: designId, error: dErr } = await db.rpc("idg_record_design", {
    p_subject: subjectId, p_user: userId, p_external_ref: ref, p_prompt: r.prompt, p_room_type: r.roomType, p_theme: r.theme,
    p_ref_image_key: refKey, p_image_keys: imageKeys,
  });
  if (dErr) { console.error("idg_record_design failed", dErr.code); return fail(500, "internal"); }
  return Response.json({ status: "success", design_id: designId, space_id: subjectId, image_keys: imageKeys });
}
