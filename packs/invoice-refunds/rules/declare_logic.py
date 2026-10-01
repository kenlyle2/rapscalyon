"""invoice-refunds rules in GenAI-Logic (LogicBank) form.

STATUS: written against the rule syntax in the GenAI-Logic documentation (Rule.sum, Rule.formula, Rule.copy,
Rule.constraint with calling=, Rule.commit_row_event). It has NOT been run: GenAI-Logic is not part of RapScalYon yet.
The same rules are enforced today by the SQL triggers in migrations/001_init.sql, and tests/001.sql proves them.
Model names assume a generated SQLAlchemy model with one class per ir_* table.
"""
from decimal import Decimal

from logic_bank.logic_bank import Rule
from logic_bank.exec_row_logic.logic_row import LogicRow

import database.models as models


def declare_logic():
    # Line amount = quantity * unit_price                                   [Formula]
    Rule.formula(derive=models.InvoiceLine.amount,
                 as_expression=lambda row: row.quantity * row.unit_price)

    # Invoice total = sum of its line amounts                                [Sum]
    Rule.sum(derive=models.Invoice.total, as_sum_of=models.InvoiceLine.amount)

    # Invoice refunded_total = sum of APPROVED refunds                       [Sum, qualified]
    Rule.sum(derive=models.Invoice.refunded_total, as_sum_of=models.Refund.amount,
             where=lambda row: row.status == "approved")

    # Invoice net = total - refunded_total                                   [Formula]
    Rule.formula(derive=models.Invoice.net,
                 as_expression=lambda row: row.total - row.refunded_total)

    # Customer balance = sum of totals of invoices still owed (sent)         [Sum, qualified]
    Rule.sum(derive=models.Customer.balance, as_sum_of=models.Invoice.total,
             where=lambda row: row.status == "sent")

    # Refund currency comes from the invoice at creation and is not propagated later   [Copy]
    Rule.copy(derive=models.Refund.currency, from_parent=models.Invoice.currency)

    # A refund is only possible against a paid invoice                       [Constraint, reads the parent]
    def refund_needs_paid_invoice(row: models.Refund, old_row: models.Refund, logic_row: LogicRow):
        if row.status in ("requested", "approved"):
            return row.invoice.status == "paid"
        return True
    Rule.constraint(validate=models.Refund, calling=refund_needs_paid_invoice,
                    error_msg="Refunds are only possible against a paid invoice")

    # A refund can never exceed what remains on the invoice                  [Constraint, uses the Sum and Formula above]
    def refund_within_remaining(row: models.Refund, old_row: models.Refund, logic_row: LogicRow):
        if row.status in ("requested", "approved"):
            other_approved = row.invoice.refunded_total - (row.amount if row.status == "approved" else Decimal(0))
            return row.amount <= row.invoice.total - other_approved
        return True
    Rule.constraint(validate=models.Refund, calling=refund_within_remaining,
                    error_msg="Refund exceeds what remains on the invoice")

    # Invoice invariant: refunds never exceed the total (also fires when a line is lowered)   [Constraint]
    Rule.constraint(validate=models.Invoice,
                    as_condition=lambda row: row.refunded_total <= row.total,
                    error_msg="Refunds cannot exceed the invoice total")

    # A decided refund cannot change (state transition via old_row)          [Constraint]
    def decided_is_final(row: models.Refund, old_row: models.Refund, logic_row: LogicRow):
        if logic_row.ins_upd_dlt == "upd" and old_row.status != "requested":
            return row.status == old_row.status
        return True
    Rule.constraint(validate=models.Refund, calling=decided_is_final, error_msg="A decided refund cannot change")

    # Approval writes an outbox event for a worker to email the customer     [Event]
    def refund_approved(row: models.Refund, old_row: models.Refund, logic_row: LogicRow):
        if row.status == "approved" and (logic_row.ins_upd_dlt == "ins" or old_row.status != "approved"):
            logic_row.log("refund approved: queue customer notification")
            # insert a models.RefundEvent row here
    Rule.commit_row_event(on_class=models.Refund, calling=refund_approved)
