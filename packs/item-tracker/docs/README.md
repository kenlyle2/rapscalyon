# item-tracker
The base class for anything a subject tracks. An *item* has a `kind` (a lowercase slug such as `job`), a title, an optional link, source and notes,
and an append-only event log. Item-tracker knows nothing about any one kind: child packs (for example the commercial `jobs-tracker`) add a 1:1 table keyed on
`it_items (id, subject_id)` with typed columns, and write their own `status_change` events through `it_log_event`.

Writing a child: create `<prefix>_<name>(item_id, subject_id, ...)` with `foreign key (item_id, subject_id) references it_items (id, subject_id) on delete cascade`,
enforce `kind` in a trigger, and expose one SECURITY DEFINER function that inserts the base row and the child row together.
The `jobs-tracker` pack (commercial, see rapscalyon-plus) is the reference child;

Plan cap: `it_max_items` (default 100 unarchived items per subject). Service-role code and migrations are exempt.
Deleting an item is owner-only and cascades to its child row and events.
