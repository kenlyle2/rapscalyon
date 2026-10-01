import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

export type Subject = { id: string; name: string; kind: "individual" | "business"; owner_id: string };

/** The workspace the user is acting in: cookie choice if RLS lets them see it, else their first one, else null. */
export async function currentSubject(): Promise<Subject | null> {
  const supabase = await supabaseServer();
  const { data } = await supabase.from("subjects").select("id,name,kind,owner_id").order("created_at");
  const list = (data ?? []) as Subject[];
  const chosen = (await cookies()).get("rs_subject")?.value;
  return list.find((s) => s.id === chosen) ?? list[0] ?? null;
}

/** For pack pages: returns the active subject or sends the user to create one. */
export async function requireSubject(): Promise<Subject> {
  const s = await currentSubject();
  if (!s) redirect("/subjects");
  return s;
}
