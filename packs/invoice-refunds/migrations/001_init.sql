-- invoice-refunds: customers, invoices, lines, refunds. Derived columns (line amount, invoice total/refunded/net, customer balance)
-- are written only by triggers; clients cannot set them. Rules are declared in rules/declare_logic.py (GenAI-Logic form) and enforced here in SQL.
create table public.ir_customers (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  name        text not null check (length(name) between 1 and 200),
  email       text check (email is null or length(email) <= 320),
  balance     numeric(12,2) not null default 0,            -- derived: sum of totals of invoices in status 'sent'
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, subject_id)
);
create index ir_customers_subject_idx on public.ir_customers (subject_id, created_at desc);
create trigger ir_customers_updated_at before update on public.ir_customers for each row execute function public.set_updated_at();

create table public.ir_invoices (
  id              uuid primary key default gen_random_uuid(),
  subject_id      uuid not null,
  customer_id     uuid not null,
  number          text not null check (length(number) between 1 and 40),
  currency        text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  status          text not null default 'draft' check (status in ('draft', 'sent', 'paid', 'void')),
  notes           text check (notes is null or length(notes) <= 5000),
  total           numeric(12,2) not null default 0,         -- derived: sum of line amounts
  refunded_total  numeric(12,2) not null default 0,         -- derived: sum of approved refunds
  net             numeric(12,2) generated always as (total - refunded_total) stored,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, subject_id),
  unique (subject_id, number),
  foreign key (customer_id, subject_id) references public.ir_customers (id, subject_id) on delete restrict
);
create index ir_invoices_customer_idx on public.ir_invoices (customer_id, subject_id);
create trigger ir_invoices_updated_at before update on public.ir_invoices for each row execute function public.set_updated_at();

create table public.ir_invoice_lines (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null,
  subject_id  uuid not null,
  description text not null check (length(description) between 1 and 500),
  quantity    numeric(12,3) not null check (quantity > 0),
  unit_price  numeric(12,2) not null check (unit_price >= 0),
  amount      numeric(12,2) not null default 0,             -- derived: quantity * unit_price
  foreign key (invoice_id, subject_id) references public.ir_invoices (id, subject_id) on delete cascade
);
create index ir_invoice_lines_invoice_idx on public.ir_invoice_lines (invoice_id, subject_id);

create table public.ir_refunds (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null,
  subject_id  uuid not null,
  amount      numeric(12,2) not null check (amount > 0),
  currency    text not null,                                 -- copied from the invoice at creation, never changes
  status      text not null default 'requested' check (status in ('requested', 'approved', 'rejected')),
  reason      text check (reason is null or length(reason) <= 2000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (invoice_id, subject_id) references public.ir_invoices (id, subject_id) on delete restrict
);
create index ir_refunds_invoice_idx on public.ir_refunds (invoice_id, subject_id);
create trigger ir_refunds_updated_at before update on public.ir_refunds for each row execute function public.set_updated_at();

-- Outbox for approved refunds (the "event" rule). A worker can pick rows up to email the customer; clients can only read it.
create table public.ir_refund_events (
  id          uuid primary key default gen_random_uuid(),
  refund_id   uuid not null references public.ir_refunds(id) on delete restrict,
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  kind        text not null check (kind in ('refund_approved')),
  amount      numeric(12,2) not null,
  currency    text not null,
  occurred_at timestamptz not null default now()
);
create index ir_refund_events_refund_idx on public.ir_refund_events (refund_id);
create index ir_refund_events_subject_idx on public.ir_refund_events (subject_id, occurred_at desc);

-- Recompute helpers (definer: they write derived columns that clients may not touch).
create function public.ir_recalc_customer(p_customer uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.ir_customers c set balance = coalesce((select sum(i.total) from public.ir_invoices i where i.customer_id = c.id and i.status = 'sent'), 0)
   where c.id = p_customer;
end $$;

create function public.ir_recalc_invoice(p_invoice uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.ir_invoices i set
    total = coalesce((select sum(l.amount) from public.ir_invoice_lines l where l.invoice_id = i.id), 0),
    refunded_total = coalesce((select sum(r.amount) from public.ir_refunds r where r.invoice_id = i.id and r.status = 'approved'), 0)
   where i.id = p_invoice;
end $$;

-- Rule: line amount = quantity * unit_price (Formula). Lines may change only while the invoice is a draft (Constraint).
create function public.ir_line_before() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  select status into v_status from public.ir_invoices where id = coalesce(new.invoice_id, old.invoice_id);
  -- a cascade from deleting a draft invoice arrives after the invoice row is gone (v_status is null): allow it
  if v_status is distinct from 'draft' and not (tg_op = 'DELETE' and v_status is null) then
    raise exception 'ir: lines can only change while the invoice is a draft' using errcode = 'check_violation';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.amount := round(new.quantity * new.unit_price, 2);
  return new;
end $$;
create trigger ir_invoice_lines_before before insert or update or delete on public.ir_invoice_lines for each row execute function public.ir_line_before();

-- Rule: invoice total = sum of line amounts (Sum).
create function public.ir_line_after() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.ir_recalc_invoice(coalesce(new.invoice_id, old.invoice_id));
  return null;
end $$;
create trigger ir_invoice_lines_after after insert or update or delete on public.ir_invoice_lines for each row execute function public.ir_line_after();

-- Invoice constraints: allowed status moves; no void while refunds exist; refunded never exceeds total; deletes only for drafts.
create function public.ir_invoice_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then raise exception 'ir: only draft invoices can be deleted' using errcode = 'check_violation'; end if;
    return old;
  end if;
  if new.status is distinct from old.status then
    if not ((old.status = 'draft' and new.status in ('sent', 'void'))
         or (old.status = 'sent' and new.status in ('paid', 'void'))
         or (old.status = 'paid' and new.status = 'void')) then
      raise exception 'ir: invoice cannot move from % to %', old.status, new.status using errcode = 'check_violation';
    end if;
    if new.status = 'void' and exists (select 1 from public.ir_refunds r where r.invoice_id = new.id and r.status in ('requested', 'approved')) then
      raise exception 'ir: an invoice with open or approved refunds cannot be voided' using errcode = 'check_violation';
    end if;
    if new.status = 'sent' and new.total <= 0 then
      raise exception 'ir: an invoice needs a positive total before it is sent' using errcode = 'check_violation';
    end if;
  end if;
  if new.refunded_total > new.total then
    raise exception 'ir: refunds (%) cannot exceed the invoice total (%)', new.refunded_total, new.total using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger ir_invoices_before before update or delete on public.ir_invoices for each row execute function public.ir_invoice_before();

-- Rule: customer balance = sum of totals of 'sent' invoices (Sum with a qualifier).
create function public.ir_invoice_after() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then perform public.ir_recalc_customer(old.customer_id); return null; end if;
  perform public.ir_recalc_customer(new.customer_id);
  return null;
end $$;
create trigger ir_invoices_after after insert or update or delete on public.ir_invoices for each row execute function public.ir_invoice_after();

-- Refund rules: copy currency from the invoice (Copy); invoice must be Paid; amount must fit what remains; only the owner decides;
-- requested -> approved|rejected only, once (Constraints).
create function public.ir_refund_before() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_inv public.ir_invoices%rowtype; v_other numeric(12,2);
begin
  select * into v_inv from public.ir_invoices where id = new.invoice_id;
  if tg_op = 'INSERT' then
    new.currency := v_inv.currency;
    new.status := 'requested';
  else
    if new.invoice_id <> old.invoice_id or new.amount <> old.amount or new.currency <> old.currency then
      raise exception 'ir: only the status of a refund can change' using errcode = 'check_violation';
    end if;
    if new.status is distinct from old.status then
      if old.status <> 'requested' then raise exception 'ir: a decided refund cannot change' using errcode = 'check_violation'; end if;
      if (select auth.uid()) is not null and not public.is_subject_owner(new.subject_id) then
        raise exception 'ir: only the workspace owner can decide a refund' using errcode = '42501';
      end if;
    end if;
  end if;
  if new.status in ('requested', 'approved') then
    if v_inv.status <> 'paid' then raise exception 'ir: refunds are only possible against a paid invoice' using errcode = 'check_violation'; end if;
    select coalesce(sum(r.amount), 0) into v_other from public.ir_refunds r where r.invoice_id = new.invoice_id and r.status = 'approved' and r.id is distinct from new.id;
    if new.amount > v_inv.total - v_other then
      raise exception 'ir: refund (%) exceeds what remains on the invoice (%)', new.amount, v_inv.total - v_other using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
create trigger ir_refunds_before before insert or update on public.ir_refunds for each row execute function public.ir_refund_before();

-- Rule: invoice refunded_total = sum of approved refunds (Sum); approval writes an outbox event (Event).
create function public.ir_refund_after() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.ir_recalc_invoice(new.invoice_id);
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    insert into public.ir_refund_events (refund_id, subject_id, kind, amount, currency) values (new.id, new.subject_id, 'refund_approved', new.amount, new.currency);
  end if;
  return null;
end $$;
create trigger ir_refunds_after after insert or update on public.ir_refunds for each row execute function public.ir_refund_after();

alter table public.ir_customers enable row level security;
alter table public.ir_invoices enable row level security;
alter table public.ir_invoice_lines enable row level security;
alter table public.ir_refunds enable row level security;
alter table public.ir_refund_events enable row level security;
create policy ir_customers_select on public.ir_customers for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ir_customers_insert on public.ir_customers for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ir_customers_update on public.ir_customers for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ir_customers_delete on public.ir_customers for delete to authenticated using ((select public.is_subject_owner(subject_id)));
create policy ir_invoices_select on public.ir_invoices for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ir_invoices_insert on public.ir_invoices for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ir_invoices_update on public.ir_invoices for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ir_invoices_delete on public.ir_invoices for delete to authenticated using ((select public.is_subject_owner(subject_id)));
create policy ir_invoice_lines_select on public.ir_invoice_lines for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ir_invoice_lines_insert on public.ir_invoice_lines for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ir_invoice_lines_update on public.ir_invoice_lines for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ir_invoice_lines_delete on public.ir_invoice_lines for delete to authenticated using ((select public.has_subject_access(subject_id)));
create policy ir_refunds_select on public.ir_refunds for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy ir_refunds_insert on public.ir_refunds for insert to authenticated with check ((select public.has_subject_access(subject_id)));
create policy ir_refunds_update on public.ir_refunds for update to authenticated using ((select public.has_subject_access(subject_id))) with check ((select public.has_subject_access(subject_id)));
create policy ir_refund_events_select on public.ir_refund_events for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.ir_customers');
select public.apply_mfa_gate('public.ir_invoices');
select public.apply_mfa_gate('public.ir_invoice_lines');
select public.apply_mfa_gate('public.ir_refunds');
select public.apply_mfa_gate('public.ir_refund_events');

grant select, delete on public.ir_customers to authenticated;
grant insert (subject_id, name, email) on public.ir_customers to authenticated;
grant update (name, email) on public.ir_customers to authenticated;
grant select, delete on public.ir_invoices to authenticated;
grant insert (subject_id, customer_id, number, currency, notes) on public.ir_invoices to authenticated;
grant update (status, notes) on public.ir_invoices to authenticated;
grant select, delete on public.ir_invoice_lines to authenticated;
grant insert (invoice_id, subject_id, description, quantity, unit_price) on public.ir_invoice_lines to authenticated;
grant update (description, quantity, unit_price) on public.ir_invoice_lines to authenticated;
grant select on public.ir_refunds to authenticated;
grant insert (invoice_id, subject_id, amount, reason) on public.ir_refunds to authenticated;
grant update (status) on public.ir_refunds to authenticated;
grant select on public.ir_refund_events to authenticated;
