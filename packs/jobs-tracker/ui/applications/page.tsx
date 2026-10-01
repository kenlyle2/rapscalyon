import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

const STATUSES = ["saved", "applied", "interviewing", "offer", "rejected", "withdrawn"] as const;

async function add(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  const url = String(formData.get("url") ?? "").trim();
  await (await supabaseServer()).from("jb_applications").insert({
    subject_id: subject.id, company: String(formData.get("company")).trim(), title: String(formData.get("title")).trim(), url: url || null,
  });
  revalidatePath("/applications");
}

async function setStatus(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("jb_applications").update({ status: String(formData.get("status")) }).eq("id", String(formData.get("id")));
  revalidatePath("/applications");
}

async function remove(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("jb_applications").delete().eq("id", String(formData.get("id")));
  revalidatePath("/applications");
}

export default async function Applications() {
  const subject = await requireSubject();
  const { data: apps } = await (await supabaseServer()).from("jb_applications").select("id,company,title,url,status,applied_at").eq("subject_id", subject.id).order("created_at", { ascending: false });
  return (
    <>
      <h1>Applications</h1>
      <Card title="Track a job">
        <form action={add} style={formStyle}>
          <Field label="Company"><input name="company" required maxLength={200} /></Field>
          <Field label="Title"><input name="title" required maxLength={200} /></Field>
          <Field label="Posting URL"><input name="url" type="url" /></Field>
          <button>Add</button>
        </form>
      </Card>
      {STATUSES.map((st) => {
        const rows = (apps ?? []).filter((a) => a.status === st);
        if (!rows.length) return null;
        return (
          <Card key={st} title={`${st} (${rows.length})`}>
            {rows.map((a) => (
              <div key={a.id} style={rowStyle}>
                <strong>{a.company}</strong> {a.url ? <a href={a.url} rel="noopener noreferrer" target="_blank">{a.title}</a> : a.title}
                <form action={setStatus} style={rowStyle}>
                  <input type="hidden" name="id" value={a.id} />
                  <select name="status" defaultValue={a.status}>{STATUSES.map((s) => <option key={s}>{s}</option>)}</select>
                  <button>Move</button>
                </form>
                <form action={remove}><input type="hidden" name="id" value={a.id} /><button>Delete</button></form>
              </div>
            ))}
          </Card>
        );
      })}
    </>
  );
}
