import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { currentSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

async function create(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const kind = formData.get("kind") === "business" ? "business" : "individual";
  const { data } = await supabase.from("subjects").insert({ owner_id: user.id, kind, name: String(formData.get("name") ?? "").trim() }).select("id").single();
  if (data) (await cookies()).set("rs_subject", data.id, { path: "/", httpOnly: true, sameSite: "lax" });
  revalidatePath("/", "layout");
}

async function choose(formData: FormData) {
  "use server";
  (await cookies()).set("rs_subject", String(formData.get("id")), { path: "/", httpOnly: true, sameSite: "lax" });
  revalidatePath("/", "layout");
}

export default async function Subjects() {
  const supabase = await supabaseServer();
  const { data: subjects } = await supabase.from("subjects").select("id,name,kind").order("created_at");
  const active = await currentSubject();
  return (
    <>
      <h1>Workspaces</h1>
      <Card title="Your workspaces">
        {(subjects ?? []).length === 0 && <p>You don&apos;t have a workspace yet. Create one below.</p>}
        {(subjects ?? []).map((s) => (
          <form key={s.id} action={choose} style={rowStyle}>
            <input type="hidden" name="id" value={s.id} />
            <strong>{s.name}</strong> <span>({s.kind})</span>
            {active?.id === s.id ? <em>active</em> : <button>Use this</button>}
          </form>
        ))}
      </Card>
      <Card title="New workspace">
        <form action={create} style={formStyle}>
          <Field label="Name"><input name="name" required maxLength={200} /></Field>
          <Field label="Type"><select name="kind"><option value="individual">Individual</option><option value="business">Business</option></select></Field>
          <button>Create</button>
        </form>
      </Card>
    </>
  );
}
