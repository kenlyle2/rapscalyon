// POST /api/turnstile/verify  { token, action } -> { ok }
// Verifies a Turnstile token server-side, records failures (hashed IP only) and refuses clients with repeated failures.
import { createHmac } from "node:crypto";
import { supabaseService } from "@/lib/supabase/service";

export async function POST(req: Request) {
  const secret = process.env.TURNSTILE_SECRET_KEY, salt = process.env.TURNSTILE_IP_SALT;
  if (!secret || !salt) return Response.json({ ok: false, error: "not configured" }, { status: 500 });
  const { token, action } = await req.json().catch(() => ({}));
  if (typeof token !== "string" || typeof action !== "string" || !/^[a-z][a-z0-9_.-]{1,63}$/.test(action))
    return Response.json({ ok: false }, { status: 400 });
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
  const ipHash = createHmac("sha256", salt).update(ip).digest("hex");
  const db = supabaseService();
  const { data: recent } = await db.rpc("ts_recent_failures", { p_ip_hash: ipHash, p_minutes: 15 });
  if (Number(recent) >= 10) return Response.json({ ok: false, error: "too many failures" }, { status: 429 });
  const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ secret, response: token, remoteip: ip }),
  });
  const out = await res.json().catch(() => ({ success: false }));
  if (out.success) return Response.json({ ok: true });
  await db.rpc("ts_record_failure", { p_action: action, p_ip_hash: ipHash, p_reason: (out["error-codes"] ?? ["failed"]).join(",") });
  return Response.json({ ok: false }, { status: 400 });
}
