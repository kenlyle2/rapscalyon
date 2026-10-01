import type { ReactNode } from "react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { packRegistry } from "@/lib/packs/registry.generated";
import { currentSubject } from "@/lib/subject";

async function signOut() {
  "use server";
  await (await supabaseServer()).auth.signOut();
  redirect("/login");
}

export default async function AppLayout({ children }: { children: ReactNode }) {
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("is_admin").eq("id", user.id).single();
  const subject = await currentSubject();
  const nav = packRegistry.nav.filter((e) => (e.group === "admin" ? !!me?.is_admin : true));
  return (
    <div style={{ display: "grid", gridTemplateColumns: "220px 1fr", minHeight: "100vh" }}>
      <nav style={{ padding: 16, borderRight: "1px solid #ddd" }}>
        <Link href="/"><strong>Home</strong></Link>
        <p style={{ fontSize: 13 }}><Link href="/subjects">{subject ? subject.name : "Create a workspace"}</Link></p>
        <ul style={{ listStyle: "none", padding: 0 }}>
          {nav.map((e) => (<li key={e.pack + e.href}><Link href={e.href}>{e.label}</Link></li>))}
        </ul>
        <form action={signOut}><button>Sign out</button></form>
      </nav>
      <main style={{ padding: 24 }}>{children}</main>
    </div>
  );
}
