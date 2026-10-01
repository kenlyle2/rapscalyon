import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { Card, formStyle } from "@/components/ui";

async function save(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const analytics = formData.get("analytics") === "on", session_replay = analytics && formData.get("session_replay") === "on";
  const { data: existing } = await supabase.from("ph_consent").select("profile_id").maybeSingle();
  if (existing) await supabase.from("ph_consent").update({ analytics, session_replay }).eq("profile_id", user.id);
  else await supabase.from("ph_consent").insert({ profile_id: user.id, analytics, session_replay });
  revalidatePath("/settings/privacy");
}

export default async function Privacy() {
  const { data: c } = await (await supabaseServer()).from("ph_consent").select("analytics,session_replay").maybeSingle();
  return (
    <>
      <h1>Privacy</h1>
      <Card>
        <form action={save} style={formStyle}>
          <label><input type="checkbox" name="analytics" defaultChecked={c?.analytics ?? true} /> Share anonymous product usage to help improve the app</label>
          <label><input type="checkbox" name="session_replay" defaultChecked={c?.session_replay ?? false} /> Allow session recordings (requires usage sharing)</label>
          <button>Save</button>
        </form>
      </Card>
    </>
  );
}
