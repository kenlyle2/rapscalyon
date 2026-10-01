# invoice-refunds
Customers, invoices, line items and refunds, with the money rules enforced by the database rather than by application code.

## Rules (each is tested in `tests/001.sql`)
| Rule | Kind (GenAI-Logic term) |
|---|---|
| line amount = quantity x unit price | Formula |
| invoice total = sum of its line amounts | Sum |
| customer balance = sum of totals of invoices in status `sent` | Sum, qualified |
| invoice refunded_total = sum of `approved` refunds; net = total - refunded_total | Sum, Formula |
| a refund's currency is copied from its invoice at creation | Copy |
| a refund needs a `paid` invoice | Constraint (reads the parent) |
| a refund cannot exceed what remains on the invoice, counting approved refunds only | Constraint |
| invoice status moves draft -> sent -> paid, and any state -> void except paid-with-refunds | Constraint |
| lines change only while the invoice is a draft; only drafts are deleted | Constraint |
| only the workspace owner approves or rejects; a decided refund is final | Constraint |
| approval writes a `refund_approved` event to an outbox | Event |

Derived columns are never writable by clients (column grants), only by the triggers.

## Two implementations of the same rules
- **Today:** SQL triggers in `migrations/001_init.sql`, tested against role-switched sessions. This is what runs.
- **GenAI-Logic form:** `rules/declare_logic.py`, written from the GenAI-Logic documentation. It has **not been run**; GenAI-Logic is not part of RapScalYon yet. It exists to show the rules in declarative form and to be the starting point of a proof of concept.

## Open questions for a GenAI-Logic integration
- GenAI-Logic generates its API and enforces rules in its own process, with its own authorization. RapScalYon's guarantees (row-level security per workspace, MFA gate) live in Postgres. The documentation we hold does not say how the two fit; asked of the maintainers.
- The SQL here recomputes derived values from scratch; GenAI-Logic adjusts them incrementally. Results should match; a side-by-side run would prove it.

## Not included
Payments or card refunds (this records the decision; money movement belongs to your payment system), tax, multi-currency conversion, PDF invoices, UI pages and nav entries.
