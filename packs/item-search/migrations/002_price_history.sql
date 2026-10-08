-- item-search 0.2.0: a price history per candidate, for every kind of item.
-- A child pack that keeps a price calls is_record_price() whenever it sets or changes one (normally from its own trigger); one row is kept per change, with the time, the price in US$ (the comparable figure), the price as the seller typed it in the listing's own currency, and where the change came from.
create table public.is_price_history (
  id           uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.is_candidates (id) on delete cascade,
  subject_id   uuid not null references public.subjects (id) on delete cascade,
  at           timestamptz not null default clock_timestamp(),
  price_usd    numeric not null check (price_usd >= 0),
  price_native numeric check (price_native is null or price_native >= 0),
  currency     text check (currency is null or length(currency) between 1 and 8),
  source       text not null check (source ~ '^[a-z][a-z0-9_]{0,29}$')
);
create index is_price_history_candidate_idx on public.is_price_history (candidate_id, at desc);
create index is_price_history_subject_idx on public.is_price_history (subject_id);
alter table public.is_price_history enable row level security;
create policy is_price_history_select on public.is_price_history for select to authenticated using ((select public.has_subject_access(subject_id)));
grant select on public.is_price_history to authenticated;
select public.apply_mfa_gate('public.is_price_history');

-- Not callable by browser roles: only code that already runs with the owner's rights (a child pack's trigger or function) and the service role may write history.
create function public.is_record_price(p_candidate uuid, p_price_usd numeric, p_price_native numeric, p_currency text, p_source text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_subject uuid; v_last numeric;
begin
  select subject_id into v_subject from public.is_candidates where id = p_candidate;
  if v_subject is null or p_price_usd is null then return; end if;
  select price_usd into v_last from public.is_price_history where candidate_id = p_candidate order by at desc, id limit 1;
  if v_last is not distinct from p_price_usd then return; end if;   -- no change, no row
  insert into public.is_price_history (candidate_id, subject_id, price_usd, price_native, currency, source)
  values (p_candidate, v_subject, p_price_usd, p_price_native, p_currency, p_source);
end $$;
revoke all on function public.is_record_price(uuid, numeric, numeric, text, text) from public, anon, authenticated;
