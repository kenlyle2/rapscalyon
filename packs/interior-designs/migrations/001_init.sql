-- interior-designs: BKIDA's interior_designs row, as a child of item-tracker (kind 'interior_design').
-- Clients never write this table. They call idg_request_design (charges credits, creates the item and a queued job).
-- The executor (service role) runs the model call and reports back through idg_mark_started / idg_complete / idg_fail.
-- Webhook signature checks live in the executor, not here; the database makes every step idempotent.
create table public.idg_designs (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  prompt         text not null check (length(prompt) between 1 and 2000),
  room_type      text not null check (length(room_type) between 1 and 60),
  theme          text not null check (length(theme) between 1 and 60),
  ref_image_key  text check (ref_image_key is null or (ref_image_key ~ '^[A-Za-z0-9_./-]{1,255}$' and ref_image_key !~ '\.\.')),
  prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200),
  status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed')),
  error          text check (error is null or length(error) <= 2000),
  image_keys     text[] not null default '{}' check (cardinality(image_keys) <= 8),
  cost           integer not null check (cost >= 0),
  charge_key     text,   -- null for designs recorded from an external generator (no core charge)
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index idg_designs_item_subject_idx on public.idg_designs (item_id, subject_id);
create index idg_designs_subject_status_idx on public.idg_designs (subject_id, status, created_at desc);
create index idg_designs_requested_by_idx on public.idg_designs (requested_by);

create function public.idg_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'interior_design') then
    raise exception 'idg_designs requires an item of kind interior_design' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger idg_designs_kind before insert on public.idg_designs for each row execute function public.idg_check_kind();

-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.idg_request_design(p_subject uuid, p_prompt text, p_room_type text, p_theme text, p_ref_image_key text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select credit_cost from public.operation_pricing where operation = 'idg.generate'), 1) into v_cost;
  v_key := 'idg:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, 'idg.generate', 'idg_design', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'interior_design', left(p_room_type || ' - ' || p_theme, 200), 'idg');
  insert into public.idg_designs (item_id, subject_id, requested_by, prompt, room_type, theme, ref_image_key, cost, charge_key)
    values (v_id, p_subject, v_user, p_prompt, p_room_type, p_theme, p_ref_image_key, v_cost, v_key);
  return v_id;
end $$;
revoke execute on function public.idg_request_design(uuid, text, text, text, text) from public, anon;
grant execute on function public.idg_request_design(uuid, text, text, text, text) to authenticated;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.idg_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.idg_designs set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.idg_complete(p_item uuid, p_image_keys text[]) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.idg_designs set status = 'succeeded', image_keys = coalesce(p_image_keys, '{}'), error = null, completed_at = now()
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.idg_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.idg_designs%rowtype;
begin
  update public.idg_designs set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', 'idg.generate', 'idg_design', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;
-- Records a design generated outside core (for example by a Pickaxe action), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. The caller must already have copied the images into
-- our own storage (keys only) because the generator's result URLs expire.
create function public.idg_record_design(p_subject uuid, p_user uuid, p_external_ref text, p_prompt text, p_room_type text, p_theme text,
                                         p_ref_image_key text, p_image_keys text[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('idg:' || p_external_ref, 0));
  select item_id into v_existing from public.idg_designs where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'interior_design', left(p_room_type || ' - ' || p_theme, 200), 'idg');
  insert into public.idg_designs (item_id, subject_id, requested_by, prompt, room_type, theme, ref_image_key, prediction_id, status, image_keys, cost, completed_at)
    values (v_id, p_subject, p_user, p_prompt, p_room_type, p_theme, p_ref_image_key, p_external_ref, 'succeeded', coalesce(p_image_keys, '{}'), 0, now());
  return v_id;
end $$;
revoke execute on function public.idg_mark_started(uuid, text), public.idg_complete(uuid, text[]), public.idg_fail(uuid, text), public.idg_record_design(uuid, uuid, text, text, text, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.idg_check_kind() from public, anon, authenticated;

alter table public.idg_designs enable row level security;
create policy idg_designs_select on public.idg_designs for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.idg_designs');
grant select on public.idg_designs to authenticated;
