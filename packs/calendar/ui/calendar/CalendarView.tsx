"use client";
import { useState } from "react";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";

export type CalEvent = { id: string; title: string; start: string; end: string; allDay: boolean; kind: string; status: string; readOnly: boolean };

export default function CalendarView({ events, create, remove }: {
  events: CalEvent[];
  create: (formData: FormData) => Promise<void>;
  remove: (formData: FormData) => Promise<void>;
}) {
  const [picked, setPicked] = useState<CalEvent | null>(null);
  const [adding, setAdding] = useState(false);
  // the browser knows the viewer's time zone; send absolute instants so the server never guesses one
  const submit = (e: React.FormEvent<HTMLFormElement>) => {
    const f = e.currentTarget;
    for (const name of ["starts_at", "ends_at"]) {
      const el = f.elements.namedItem(name) as HTMLInputElement;
      el.value = new Date(el.value).toISOString();
    }
  };
  return (
    <>
      <FullCalendar
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        initialView="dayGridMonth"
        headerToolbar={{ left: "prev,next today", center: "title", right: "dayGridMonth,timeGridWeek,timeGridDay" }}
        height="auto"
        events={events.map((e) => ({ ...e, classNames: [`cal-${e.status}`] }))}
        eventClick={(info) => setPicked(events.find((e) => e.id === info.event.id) ?? null)}
      />
      {picked && (
        <p>
          <strong>{picked.title}</strong> ({picked.kind}, {picked.status}) {new Date(picked.start).toLocaleString()}
          {!picked.readOnly && (
            <form action={remove} style={{ display: "inline", marginLeft: 8 }}>
              <input type="hidden" name="id" value={picked.id} />
              <button>Delete</button>
            </form>
          )}
        </p>
      )}
      <p><button type="button" onClick={() => setAdding(!adding)}>{adding ? "Close" : "New event"}</button></p>
      {adding && (
        <form action={create} onSubmit={submit} style={{ display: "grid", gap: 8, maxWidth: 420 }}>
          <label>Title<input name="title" required maxLength={200} /></label>
          <label>Starts<input name="starts_at" type="datetime-local" required /></label>
          <label>Ends<input name="ends_at" type="datetime-local" required /></label>
          <label><input name="all_day" type="checkbox" /> All day</label>
          <label>Kind<input name="kind" defaultValue="event" pattern="[a-z][a-z0-9_]{1,39}" /></label>
          <button>Save</button>
        </form>
      )}
    </>
  );
}
