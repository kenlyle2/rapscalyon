"""SQLAlchemy models mirroring the ir_* tables, for running declare_logic.py. SQLite, no RLS: this proves rule semantics only."""
from decimal import Decimal
from sqlalchemy import DECIMAL, ForeignKey, String
from sqlalchemy.orm import Mapped, declarative_base, mapped_column, relationship

# LogicBank requires the classic declarative_base() metaclass (it rejects 2.0-style DeclarativeBase subclasses).
Base = declarative_base()


Money = DECIMAL(12, 2)


class Customer(Base):
    __tablename__ = "ir_customers"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    balance: Mapped[Decimal] = mapped_column(Money, default=Decimal(0))
    invoices = relationship("Invoice", back_populates="customer")


class Invoice(Base):
    __tablename__ = "ir_invoices"
    id: Mapped[int] = mapped_column(primary_key=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("ir_customers.id"))
    number: Mapped[str] = mapped_column(String(40))
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    status: Mapped[str] = mapped_column(String(10), default="draft")
    total: Mapped[Decimal] = mapped_column(Money, default=Decimal(0))
    refunded_total: Mapped[Decimal] = mapped_column(Money, default=Decimal(0))
    net: Mapped[Decimal] = mapped_column(Money, default=Decimal(0))
    customer = relationship("Customer", back_populates="invoices")
    lines = relationship("InvoiceLine", back_populates="invoice")
    refunds = relationship("Refund", back_populates="invoice")


class InvoiceLine(Base):
    __tablename__ = "ir_invoice_lines"
    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_id: Mapped[int] = mapped_column(ForeignKey("ir_invoices.id"))
    description: Mapped[str] = mapped_column(String(500))
    quantity: Mapped[Decimal] = mapped_column(DECIMAL(12, 3))
    unit_price: Mapped[Decimal] = mapped_column(Money)
    amount: Mapped[Decimal] = mapped_column(Money, default=Decimal(0))
    invoice = relationship("Invoice", back_populates="lines")


class Refund(Base):
    __tablename__ = "ir_refunds"
    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_id: Mapped[int] = mapped_column(ForeignKey("ir_invoices.id"))
    amount: Mapped[Decimal] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3), default="")
    status: Mapped[str] = mapped_column(String(10), default="requested")
    invoice = relationship("Invoice", back_populates="refunds")
