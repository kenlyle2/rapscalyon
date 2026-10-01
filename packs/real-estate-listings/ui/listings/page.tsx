import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

const TYPES = ["house", "apartment", "condo", "townhouse", "land", "commercial", "other"];
const STATUSES = ["draft", "active", "pending", "sold", "withdrawn"];

async function add(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  const price = Number(formData.get("price"));
  await supabase.from("rel_listings").insert({
    subject_id: subject.id, created_by: user!.id, title: String(formData.get("title")).trim(),
    property_type: String(formData.get("property_type")), price_minor: Number.isFinite(price) && price > 0 ? Math.round(price * 100) : null,
    bedrooms: formData.get("bedrooms") ? Number(formData.get("bedrooms")) : null,
  });
  revalidatePath("/listings");
}

async function setStatus(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("rel_listings").update({ status: String(formData.get("status")) }).eq("id", String(formData.get("id")));
  revalidatePath("/listings");
}

export default async function Listings() {
  const subject = await requireSubject();
  const { data: rows } = await (await supabaseServer()).from("rel_listings").select("id,title,status,property_type,price_minor,currency,bedrooms").eq("subject_id", subject.id).order("created_at", { ascending: false });
  return (
    <>
      <h1>Listings</h1>
      <Card title="New listing">
        <form action={add} style={formStyle}>
          <Field label="Title"><input name="title" required maxLength={200} /></Field>
          <Field label="Type"><select name="property_type">{TYPES.map((t) => <option key={t}>{t}</option>)}</select></Field>
          <Field label="Price"><input name="price" type="number" min="0" step="0.01" /></Field>
          <Field label="Bedrooms"><input name="bedrooms" type="number" min="0" /></Field>
          <button>Add</button>
        </form>
      </Card>
      <Card title="Your listings">
        {(rows ?? []).map((l) => (
          <div key={l.id} style={rowStyle}>
            <strong>{l.title}</strong> <span>{l.property_type}</span>
            {l.price_minor != null && <span>{(Number(l.price_minor) / 100).toLocaleString(undefined, { style: "currency", currency: l.currency })}</span>}
            <form action={setStatus} style={rowStyle}>
              <input type="hidden" name="id" value={l.id} />
              <select name="status" defaultValue={l.status}>{STATUSES.map((s) => <option key={s}>{s}</option>)}</select>
              <button>Update</button>
            </form>
          </div>
        ))}
      </Card>
    </>
  );
}
