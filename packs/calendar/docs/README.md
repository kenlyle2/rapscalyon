# calendar

A shared calendar for a subject: appointments, classes, deadlines, reminders.

## Events
`cal_events` holds a title, start, end, an all-day flag, a `kind` token you choose (`event`, `appointment`, `class`, `post`...), a status (`scheduled`, `done`, `cancelled`) and an optional person from the `people` pack (same subject enforced; erasing the person keeps the event). Staff create, edit and delete the events they typed in.

## The feed
Other features add their events through two service-role functions, so the calendar never reads their tables:
- `cal_upsert_event(subject, source, source_ref, kind, title, starts, ends, all_day, person)` adds or updates by `(subject, source, source_ref)` and is idempotent.
- `cal_remove_source(subject, source, ref)` withdraws one event, or all of a source's events when `ref` is null.

Feed events are read-only to users. The feature that owns an event is the only one that can change it.

## Page
`/calendar` shows a month, week or day view of the events in a window, a form to add an event, and a delete button on events you typed in. The view uses FullCalendar (added to `app/package.json`).
