// POST /api/billing-webhook  (provider adapter for FluentCart; copy and adapt for other providers)
// Copied to app/api/billing-webhook/route.ts by `rapscalyon.py pack add --app app`.
import { createHmac, timingSafeEqual } from "node:crypto";
import { supabaseService } from "@/lib/supabase/service";

const KINDS: Record<string, string> = {
  subscription_activated: "activated", subscription_renewed: "renewed", subscription_failing: "payment_failed",
  subscription_canceled: "canceled", subscription_expired: "expired", order_refunded: "refunded",
};

function validSignature(raw: string, header: string | null): boolean {
  const secret = process.env.BILLING_WEBHOOK_SECRET;
  if (!secret || !header) return false;
  const expected = createHmac("sha256", secret).update(raw).digest("hex");
  const a = Buffer.from(header), b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(req: Request) {
  const raw = await req.text();
  if (!validSignature(raw, req.headers.get("x-webhook-signature"))) return new Response("bad signature", { status: 401 });
  const e = JSON.parse(raw);
  const kind = KINDS[e.event];
  if (!kind) return Response.json({ ignored: e.event });
  const { data, error } = await supabaseService().rpc("bw_apply_event", {
    p_source: "fluentcart", p_external_id: String(e.id), p_kind: kind, p_payload: e,
    p_customer_ref: e.customer?.id ? String(e.customer.id) : null,
    p_subscription_ref: e.subscription?.id ? String(e.subscription.id) : null,
    p_plan_key: e.subscription?.plan_key ?? null, p_email: e.customer?.email ?? null,
    p_occurred_at: e.created_at ?? new Date().toISOString(),
  });
  if (error) return new Response("failed", { status: 500 }); // provider retries; apply is idempotent
  return Response.json({ result: data });
}
