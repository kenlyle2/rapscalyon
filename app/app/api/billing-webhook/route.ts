// POST /api/billing-webhook — generic subscription webhook. Copied to app/api/billing-webhook/route.ts by
// `rapscalyon.py pack add --app app`. Anything that can POST JSON can drive it: WooCommerce/WPSubscription or
// FluentCart through Bit Integrations, n8n, Stripe forwarders, curl.
//
// Body (flat JSON, same fields PostGlider/JobsGlider use):
//   { subscription_id, customer_id?, status, email, product_name?, product_sku?, plan_key?, event_id?, occurred_at? }
//   status: active|trialing|renewed -> activated/renewed, on-hold|failed|past_due -> payment_failed,
//           cancelled|canceled|pending-cancel -> canceled, expired -> expired, refunded -> refunded
//
// Auth (any one, checked in constant time against BILLING_WEBHOOK_SECRET):
//   x-wc-webhook-signature : base64(HMAC-SHA256(raw body))   — native WooCommerce webhooks
//   x-webhook-signature    : hex(HMAC-SHA256(raw body))      — signing senders
//   x-webhook-secret       : the shared secret itself        — Bit Integrations / simple senders (use HTTPS)
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { supabaseService } from "@/lib/supabase/service";

const eq = (a: string, b: string) => {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

function authorized(raw: string, req: Request): boolean {
  const secret = process.env.BILLING_WEBHOOK_SECRET;
  if (!secret) return false;
  const sign = (enc: "base64" | "hex") => createHmac("sha256", secret).update(raw).digest(enc);
  const wc = req.headers.get("x-wc-webhook-signature");
  if (wc && eq(wc, sign("base64"))) return true;
  const hex = req.headers.get("x-webhook-signature");
  if (hex && eq(hex.toLowerCase(), sign("hex"))) return true;
  const shared = req.headers.get("x-webhook-secret");
  return !!shared && eq(shared, secret);
}

const KIND: Record<string, string> = {
  active: "activated", trialing: "activated", activated: "activated", created: "activated",
  renewed: "renewed", renewal: "renewed",
  "on-hold": "payment_failed", failed: "payment_failed", past_due: "payment_failed", payment_failed: "payment_failed",
  cancelled: "canceled", canceled: "canceled", "pending-cancel": "canceled",
  expired: "expired", refunded: "refunded",
};

export async function POST(req: Request) {
  const raw = await req.text();
  if (!authorized(raw, req)) return Response.json({ error: "Unauthorized" }, { status: 401 });
  let e: Record<string, unknown>;
  try { e = JSON.parse(raw); } catch { return Response.json({ error: "Invalid JSON" }, { status: 400 }); }

  const status = String(e.status ?? "").toLowerCase();
  const kind = KIND[status];
  if (!kind) return Response.json({ error: `Unknown status '${status}'` }, { status: 400 });

  // Idempotency key: sender's delivery id when present, else a hash of the exact body (a redelivery is byte-identical).
  const externalId = req.headers.get("x-wc-webhook-delivery-id") ?? req.headers.get("x-webhook-id") ?? (e.event_id ? String(e.event_id) : null)
    ?? createHash("sha256").update(raw).digest("hex");
  const s = (v: unknown) => (v === undefined || v === null || v === "" ? null : String(v));
  const occurred = typeof e.occurred_at === "string" && !isNaN(Date.parse(e.occurred_at)) ? new Date(e.occurred_at).toISOString() : new Date().toISOString();

  const { data, error } = await supabaseService().rpc("bw_apply_event", {
    p_source: (s(e.source) ?? "woocommerce").toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32) || "woocommerce",
    p_external_id: externalId, p_kind: kind, p_payload: e,
    p_customer_ref: s(e.customer_id), p_subscription_ref: s(e.subscription_id),
    p_plan_key: s(e.plan_key) ?? s(e.product_name) ?? s(e.product_sku), p_email: s(e.email), p_occurred_at: occurred,
  });
  if (error) { console.error("bw_apply_event failed", error.code); return Response.json({ error: "Internal server error" }, { status: 500 }); }
  // unmatched profiles are 404 so the sender's retry/alerting can see it, like the PostGlider endpoint
  if (data === "unmatched") return Response.json({ error: "Profile not found", result: data }, { status: 404 });
  return Response.json({ status: "success", result: data });
}
