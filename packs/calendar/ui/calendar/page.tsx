import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { requireSubject } from "@/lib/subject";
import { Card } from "@/components/ui";
import CalendarView, { type CalEvent } from "./CalendarView";

const DAY = 86_400_000;

async function create(formData: FormData) {
  "use server";
  const subject = await requireSubject();
  const supabase = await supabaseServer();
  const { data: { user } } = await supabase.auth.getUser();
  const starts = new Date(String(formData.get("starts_at")));
  const ends = new Date(String(formData.get("ends_at")));
  if (Number.isNaN(starts.getTime()) || Number.isNaN(ends.getTime()) || ends < starts) return;
  await supabase.from("cal_events").insert({
    subject_id: subject.id, created_by: user!.id, title: String(formData.get("title")).trim().slice(0, 200),
    starts_at: starts.toISOString(), ends_at: ends.toISOString(), all_day: formData.get("all_day") === "on",
    kind: String(formData.get("kind") || "event"),
  });
  revalidatePath("/calendar");
}

async function remove(formData: FormData) {
  "use server";
  await (await supabaseServer()).from("cal_events").delete().eq("id", String(formData.get("id")));
  revalidatePath("/calendar");
}

export default async function Calendar() {
  const subject = await requireSubject();
  const now = Date.now();
  const { data } = await (await supabaseServer()).from("cal_events")
    .select("id,title,starts_at,ends_at,all_day,kind,status,source")
    .eq("subject_id", subject.id)
    .gte("ends_at", new Date(now - 60 * DAY).toISOString()).lte("starts_at", new Date(now + 180 * DAY).toISOString())
    .order("starts_at").limit(500);
  const events: CalEvent[] = (data ?? []).map((e) => ({
    id: e.id, title: e.title, start: e.starts_at, end: e.ends_at, allDay: e.all_day, kind: e.kind, status: e.status, readOnly: e.source !== null,
  }));
  return (
    <>
      <h1>Calendar</h1>
      <Card><CalendarView events={events} create={create} remove={remove} /></Card>
    </>
  );
}
