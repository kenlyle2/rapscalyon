// GET/POST /api/loops-email/cron/send — drains the outbox into Loops.
import { cronAuthorized } from "@/lib/cron";
import { supabaseService } from "@/lib/supabase/service";

async function drain(req: Request) {
  if (!cronAuthorized(req)) return new Response("unauthorized", { status: 401 });
  const key = process.env.LOOPS_API_KEY;
  if (!key) return new Response("LOOPS_API_KEY not set", { status: 500 });
  const db = supabaseService();
  const { data: rows, error } = await db.rpc("lp_claim_outbox", { p_limit: 50 });
  if (error) return new Response("claim failed", { status: 500 });
  let sent = 0, failed = 0;
  for (const row of rows ?? []) {
    const { data: p } = await db.from("profiles").select("email").eq("id", row.profile_id).single();
    const res = await fetch("https://app.loops.so/api/v1/events/send", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Idempotency-Key": row.id },
      body: JSON.stringify({ email: p?.email, eventName: row.event, eventProperties: row.properties }),
    });
    if (res.ok) { sent++; await db.from("lp_outbox").update({ status: "sent", sent_at: new Date().toISOString() }).eq("id", row.id); }
    else { failed++; await db.from("lp_outbox").update({ status: row.attempts >= 5 ? "failed" : "pending", last_error: `HTTP ${res.status}` }).eq("id", row.id); }
  }
  return Response.json({ sent, failed });
}
export const GET = drain, POST = drain;
