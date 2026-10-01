import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

async function create(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  const when = String(formData.get("scheduled_for") ?? "");
  await supabase.from("sp_posts").insert({
    subject_id: subject.id, created_by: user!.id, body: String(formData.get("body")).trim(),
    ...(when ? { status: "scheduled", scheduled_for: new Date(when).toISOString() } : {}),
  });
  revalidatePath("/posts");
}

async function remove(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("sp_posts").delete().eq("id", String(formData.get("id")));
  revalidatePath("/posts");
}

export default async function Posts() {
  const subject = await requireSubject();
  const { data: posts } = await (await supabaseServer()).from("sp_posts").select("id,body,status,scheduled_for,error").eq("subject_id", subject.id).order("created_at", { ascending: false }).limit(100);
  return (
    <>
      <h1>Posts</h1>
      <Card title="New post">
        <form action={create} style={formStyle}>
          <Field label="Text"><textarea name="body" required maxLength={5000} rows={4} /></Field>
          <Field label="Schedule for (leave empty to save as draft)"><input name="scheduled_for" type="datetime-local" /></Field>
          <button>Save</button>
        </form>
      </Card>
      <Card title="Your posts">
        {(posts ?? []).map((p) => (
          <div key={p.id} style={rowStyle}>
            <span>[{p.status}{p.scheduled_for ? ` ${new Date(p.scheduled_for).toLocaleString()}` : ""}]</span> {p.body}
            {p.error && <em> — {p.error}</em>}
            {["draft", "scheduled", "failed"].includes(p.status) && <form action={remove}><input type="hidden" name="id" value={p.id} /><button>Delete</button></form>}
          </div>
        ))}
      </Card>
    </>
  );
}
