import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { Card, formStyle } from "@/components/ui";

async function save(formData: FormData) {
  "use server";
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const marketing = formData.get("marketing") === "on", product = formData.get("product") === "on";
  const { data: existing } = await supabase.from("lp_preferences").select("profile_id").maybeSingle();
  if (existing) await supabase.from("lp_preferences").update({ marketing, product }).eq("profile_id", user.id);
  else await supabase.from("lp_preferences").insert({ profile_id: user.id, marketing, product });
  revalidatePath("/settings/email");
}

export default async function EmailPrefs() {
  const { data: pref } = await (await supabaseServer()).from("lp_preferences").select("marketing,product").maybeSingle();
  return (
    <>
      <h1>Email preferences</h1>
      <Card>
        <form action={save} style={formStyle}>
          <label><input type="checkbox" name="product" defaultChecked={pref?.product ?? true} /> Product updates and account notices</label>
          <label><input type="checkbox" name="marketing" defaultChecked={pref?.marketing ?? true} /> Tips, offers and newsletters</label>
          <button>Save</button>
        </form>
      </Card>
    </>
  );
}
