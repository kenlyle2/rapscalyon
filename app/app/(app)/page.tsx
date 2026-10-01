import { supabaseServer } from "@/lib/supabase/server";
import { packRegistry } from "@/lib/packs/registry.generated";

export default async function Home() {
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  const { data: limits } = await supabase.rpc("get_my_limits");
  return (
    <>
      <h1>Welcome{user?.email ? `, ${user.email}` : ""}</h1>
      <p>Installed packs contribute {packRegistry.nav.length} menu entries.</p>
      <details><summary>Your limits</summary><pre>{JSON.stringify(limits, null, 2)}</pre></details>
    </>
  );
}
