import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, Field, formStyle, rowStyle } from "@/components/ui";

async function invite(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  await (await supabaseServer()).rpc("team_invite", { p_subject_id: subject.id, p_email: String(formData.get("email")).trim().toLowerCase(), p_role: String(formData.get("role")) });
  revalidatePath("/team");
}

async function removeMember(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  await (await supabaseServer()).rpc("team_remove_member", { p_subject_id: subject.id, p_user_id: String(formData.get("user_id")) });
  revalidatePath("/team");
}

async function accept(formData: FormData) {
  "use server";
  await (await supabaseServer()).rpc("team_accept", { p_token: String(formData.get("token")).trim() });
  revalidatePath("/", "layout");
}

export default async function Team() {
  const subject = await requireSubject();
  const supabase = await supabaseServer();
  const { data: members } = await supabase.from("subject_members").select("user_id,role,accepted_at").eq("subject_id", subject.id);
  const { data: invites } = await supabase.from("team_invites").select("id,email,role,expires_at,accepted_at").eq("subject_id", subject.id).is("accepted_at", null);
  return (
    <>
      <h1>Team — {subject.name}</h1>
      <Card title="Members">
        {(members ?? []).length === 0 && <p>No other members yet.</p>}
        {(members ?? []).map((m) => (
          <form key={m.user_id} action={removeMember} style={rowStyle}>
            <input type="hidden" name="user_id" value={m.user_id} />
            <span>{m.user_id}</span> <em>{m.role}{m.accepted_at ? "" : " (pending)"}</em><button>Remove</button>
          </form>
        ))}
      </Card>
      <Card title="Pending invites">
        {(invites ?? []).map((i) => (<div key={i.id}>{i.email} — {i.role}, expires {new Date(i.expires_at).toLocaleDateString()}</div>))}
      </Card>
      <Card title="Invite by email (owner only)">
        <form action={invite} style={formStyle}>
          <Field label="Email"><input name="email" type="email" required /></Field>
          <Field label="Role"><select name="role"><option>member</option><option>viewer</option><option>admin</option></select></Field>
          <button>Invite</button>
        </form>
      </Card>
      <Card title="Accept an invite">
        <form action={accept} style={formStyle}>
          <Field label="Invite token"><input name="token" required /></Field>
          <button>Join</button>
        </form>
      </Card>
    </>
  );
}
