import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

async function add(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  await supabase.from("bw_plan_map").upsert({
    source: String(formData.get("source")).trim().toLowerCase(), plan_key: String(formData.get("plan_key")).trim(),
    tier: String(formData.get("tier")).trim().toLowerCase(), match_mode: String(formData.get("match_mode")), updated_by: user.id,
  });
  revalidatePath("/admin/billing-plans");
}

async function remove(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("bw_plan_map").delete().eq("source", String(formData.get("source"))).eq("plan_key", String(formData.get("plan_key")));
  revalidatePath("/admin/billing-plans");
}

export default async function BillingPlans() {
  const supabase = await supabaseServer();
  const { data: rows, error } = await supabase.from("bw_plan_map").select("source,plan_key,tier,match_mode").order("source");
  const { data: events } = await supabase.from("billing_events").select("id,source,event_type,processing_status,created_at").order("created_at", { ascending: false }).limit(20);
  if (error) return <p>Admins only.</p>;
  return (
    <>
      <h1>Billing plans</h1>
      <Card title="Product → tier">
        {(rows ?? []).map((r) => (
          <form key={r.source + r.plan_key} action={remove} style={rowStyle}>
            <input type="hidden" name="source" value={r.source} /><input type="hidden" name="plan_key" value={r.plan_key} />
            <code>{r.source}</code> <span>{r.match_mode === "contains" ? "name contains" : "key ="}</span> <code>{r.plan_key}</code> → <strong>{r.tier}</strong><button>Delete</button>
          </form>
        ))}
      </Card>
      <Card title="Add or change a mapping">
        <form action={add} style={formStyle}>
          <Field label="Source (e.g. woocommerce, fluentcart)"><input name="source" required defaultValue="woocommerce" /></Field>
          <Field label="Plan key or text in the product name"><input name="plan_key" required /></Field>
          <Field label="Match"><select name="match_mode"><option value="contains">name contains</option><option value="exact">exact key</option></select></Field>
          <Field label="Tier"><input name="tier" required placeholder="pro" /></Field>
          <button>Save</button>
        </form>
      </Card>
      <Card title="Recent webhook events">
        {(events ?? []).map((e) => (<div key={e.id}>{new Date(e.created_at).toLocaleString()} — {e.source} {e.event_type} — {e.processing_status}</div>))}
      </Card>
    </>
  );
}
