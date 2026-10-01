import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

async function add(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  const url = String(formData.get("url") ?? "").trim();
  await (await supabaseServer()).from("it_items").insert({
    subject_id: subject.id,
    kind: String(formData.get("kind")).trim().toLowerCase(),
    title: String(formData.get("title")).trim(),
    url: url || null,
  });
  revalidatePath("/items");
}

async function archive(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("it_items").update({ archived_at: new Date().toISOString() }).eq("id", String(formData.get("id")));
  revalidatePath("/items");
}

export default async function Items() {
  const subject = await requireSubject();
  const { data: items } = await (await supabaseServer())
    .from("it_items").select("id,kind,title,url,created_at").eq("subject_id", subject.id).is("archived_at", null).order("created_at", { ascending: false });
  return (
    <>
      <h1>Items</h1>
      <Card title="Add an item">
        <form action={add} style={formStyle}>
          <Field label="Kind"><input name="kind" required pattern="[a-z][a-z0-9_]{1,29}" defaultValue="note" /></Field>
          <Field label="Title"><input name="title" required maxLength={200} /></Field>
          <Field label="Link"><input name="url" type="url" /></Field>
          <button>Add</button>
        </form>
      </Card>
      <Card title={`Items (${items?.length ?? 0})`}>
        {(items ?? []).map((i) => (
          <div key={i.id} style={rowStyle}>
            <em>{i.kind}</em> {i.url ? <a href={i.url} rel="noopener noreferrer" target="_blank">{i.title}</a> : i.title}
            <form action={archive}><input type="hidden" name="id" value={i.id} /><button>Archive</button></form>
          </div>
        ))}
      </Card>
    </>
  );
}
