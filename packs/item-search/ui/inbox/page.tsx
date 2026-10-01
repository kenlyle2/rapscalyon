import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card, rowStyle } from "@/components/ui";

async function accept(formData: FormData) {
  "use server";
  await (await supabaseServer()).rpc("is_accept_candidate", { p_candidate: String(formData.get("id")) });
  revalidatePath("/inbox");
}
async function dismiss(formData: FormData) {
  "use server";
  await (await supabaseServer()).rpc("is_dismiss_candidate", { p_candidate: String(formData.get("id")) });
  revalidatePath("/inbox");
}
async function approve(formData: FormData) {
  "use server";
  await (await supabaseServer()).rpc("is_approve_dispatch", { p_id: String(formData.get("id")), p_delay_seconds: Number(formData.get("delay") ?? 0) });
  revalidatePath("/inbox");
}
async function cancel(formData: FormData) {
  "use server";
  await (await supabaseServer()).rpc("is_cancel_dispatch", { p_id: String(formData.get("id")) });
  revalidatePath("/inbox");
}

export default async function Inbox() {
  const subject = await requireSubject();
  const db = await supabaseServer();
  const { data: candidates } = await db.from("is_candidates").select("id,title,url,source").eq("subject_id", subject.id).eq("status", "new").order("created_at", { ascending: false }).limit(100);
  const { data: reviews } = await db.from("is_dispatches").select("id,payload,it_items(title)").eq("subject_id", subject.id).eq("status", "pending_review").order("created_at").limit(100);
  const pending = (reviews ?? []) as unknown as { id: string; it_items: { title: string } | null }[];
  return (
    <>
      <h1>Inbox</h1>
      <Card title={`Waiting for your review (${pending.length})`}>
        {pending.map((d) => (
          <div key={d.id} style={rowStyle}>
            <strong>{d.it_items?.title ?? "Item"}</strong>
            <form action={approve} style={rowStyle}>
              <input type="hidden" name="id" value={d.id} />
              <select name="delay" defaultValue="0"><option value="0">now</option><option value="3600">in 1 hour</option><option value="86400">in 24 hours</option></select>
              <button>Approve</button>
            </form>
            <form action={cancel}><input type="hidden" name="id" value={d.id} /><button>Cancel</button></form>
          </div>
        ))}
      </Card>
      <Card title={`New matches (${candidates?.length ?? 0})`}>
        {(candidates ?? []).map((c) => (
          <div key={c.id} style={rowStyle}>
            {c.url ? <a href={c.url} rel="noopener noreferrer" target="_blank">{c.title}</a> : c.title} {c.source ? <em>{c.source}</em> : null}
            <form action={accept}><input type="hidden" name="id" value={c.id} /><button>Add to my list</button></form>
            <form action={dismiss}><input type="hidden" name="id" value={c.id} /><button>Dismiss</button></form>
          </div>
        ))}
      </Card>
    </>
  );
}
