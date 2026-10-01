"""Run rules/declare_logic.py in LogicBank against SQLite and check the money rules (mirrors tests/001.sql).
Setup: python3 -m venv .venv && .venv/bin/pip install logicbank sqlalchemy && .venv/bin/python run_scenarios.py
"""
import sys
from decimal import Decimal as D
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))                 # makes `database.models` importable
sys.path.insert(0, str(HERE.parent))          # makes declare_logic importable

from logic_bank.logic_bank import LogicBank
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import database.models as m
from declare_logic import declare_logic

engine = create_engine("sqlite://")
m.Base.metadata.create_all(engine)
# expire_on_commit=False: LogicBank adjusts sums from a row's old values; expired attributes arrive without them and the adjustment is missed.
s = Session(engine, expire_on_commit=False)
LogicBank.activate(session=s, activator=declare_logic)

passed = 0
def check(ok, msg):
    global passed
    if not ok: raise SystemExit(f"FAIL: {msg}")
    passed += 1
    print("ok  ", msg)

def reset():
    # after a rejected change: roll back and reload, so the engine sees true old values on the next edit
    s.rollback(); s.expire_all()
    for o in list(s.identity_map.values()): s.refresh(o)

def denied(fn, msg):
    try:
        fn(); s.commit()
    except Exception as e:
        reset(); check(True, f"{msg}  [{type(e).__name__}]")
    else:
        reset(); check(False, f"{msg}: expected the engine to reject it")

c = m.Customer(name="Acme"); s.add(c); s.commit()
inv = m.Invoice(customer=c, number="INV-1"); s.add(inv); s.commit()
s.add_all([m.InvoiceLine(invoice=inv, description="Design", quantity=D(2), unit_price=D("40.00")),
           m.InvoiceLine(invoice=inv, description="Hosting", quantity=D(1), unit_price=D("20.00"))]); s.commit()
check(inv.total == D("100.00"), "invoice total = sum of line amounts (Formula + Sum)")

denied(lambda: s.add(m.Refund(invoice=inv, amount=D("10"))), "refund on a draft invoice is rejected (Constraint on parent)")
inv.status = "sent"; s.commit()
check(c.balance == D("100.00"), "customer balance = sum of sent invoice totals (qualified Sum)")
denied(lambda: s.add(m.Refund(invoice=inv, amount=D("10"))), "refund on an unpaid (sent) invoice is rejected")
inv.status = "paid"; s.commit()
check(c.balance == D("0.00"), "paying the invoice clears the balance")

r1 = m.Refund(invoice=inv, amount=D("60.00")); s.add(r1); s.commit()
check(r1.currency == "USD", "refund currency copied from the invoice (Copy)")
denied(lambda: s.add(m.Refund(invoice=inv, amount=D("100.01"))), "refund larger than the invoice is rejected")
r2 = m.Refund(invoice=inv, amount=D("60.00")); s.add(r2); s.commit()
r1.status = "approved"; s.commit()
check(inv.refunded_total == D("60.00") and inv.net == D("40.00"), "refunded_total = approved refunds; net = total - refunded (Sum + Formula)")
def approve_second(): r2.status = "approved"
denied(approve_second, "approving a second 60 would exceed the 100 paid")
r2 = s.get(m.Refund, r2.id); r2.status = "rejected"; s.commit()
def reopen(): r2.status = "approved"
denied(reopen, "a decided refund cannot change (state transition via old_row)")
r3 = m.Refund(invoice=inv, amount=D("40.00")); s.add(r3); s.commit()
r3.status = "approved"; s.commit()
check(inv.net == D("0.00"), "the full amount can be refunded, exactly")
denied(lambda: s.add(m.Refund(invoice=inv, amount=D("0.01"))), "nothing left to refund")
print(f"\n{passed} checks passed")
