# Invoices and refunds
> Invoices where the rules are the database's job: refunds only against paid invoices, never more than was paid.

## Who it's for
Freelancers and small businesses who invoice customers and refund them, and who want the money rules guaranteed instead of re-implemented in every screen.

## What you get
- Customers, invoices and line items with totals and balances computed for you.
- Refund requests that must reference a paid invoice, cannot exceed what remains, and are approved only by the workspace owner.
- An outbox event for every approved refund, ready for an email worker.
- The same rules written in GenAI-Logic's declarative form, as a starting point for a rules-engine backend.

## Works well with
subject-individual, subject-business, loops-email.

## Under the hood
Triggers write every derived value; clients cannot. Role-switched SQL tests try to break each rule.
