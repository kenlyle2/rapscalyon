-- youtube-content: Video-to-content records (the BuilderKit youtube_content_generator table) as a child of item-tracker: link, title, language, transcript, summary and generated content, recorded once by the server with an optional core charge in the same transaction.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.ytc_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.ytc_valid_keys(text[], integer) from public, anon, authenticated;

create table public.ytc_pieces (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  url text not null check (length(url) between 1 and 2000),
  youtube_title text not null check (length(youtube_title) between 1 and 300),
  language text check (length(language) between 1 and 40),
  external_ref   text unique check (external_ref is null or length(external_ref) <= 200),
  transcription text not null check (length(transcription) between 1 and 500000),
  summary text check (length(summary) between 1 and 50000),
  generated_content jsonb check (pg_column_size(generated_content) <= 500000),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index ytc_pieces_item_subject_idx on public.ytc_pieces (item_id, subject_id);
create index ytc_pieces_subject_created_idx on public.ytc_pieces (subject_id, created_at desc);
create index ytc_pieces_requested_by_idx on public.ytc_pieces (requested_by);

create function public.ytc_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'youtube_content') then
    raise exception 'ytc_pieces requires an item of kind youtube_content' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger ytc_pieces_kind before insert on public.ytc_pieces for each row execute function public.ytc_check_kind();


-- Records one finished item made by an outside service (the generation happens in the app server or an agent, never in the database).
-- Idempotent on p_external_ref: a replay returns the same item. p_cost > 0 charges core credits in the same transaction (refused with 53400 when short).
create function public.ytc_record(p_subject uuid, p_user uuid, p_external_ref text, p_url text, p_youtube_title text, p_language text, p_transcription text, p_summary text, p_generated_content jsonb, p_cost integer default 0) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid; v_res jsonb; v_key text;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  if p_cost is null or p_cost < 0 then raise exception 'invalid cost' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ytc:' || p_external_ref, 0));
  select item_id into v_existing from public.ytc_pieces where external_ref = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  if p_cost > 0 then
    v_key := 'ytc:' || v_id;
    v_res := public.charge_credits(p_user, p_cost, v_key, 'ytc.generate', 'ytc_pieces', v_id);
    if coalesce((v_res->>'success')::boolean, false) is not true then
      raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
    end if;
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'youtube_content', left(coalesce(p_youtube_title, 'Video content'), 200), 'ytc');
  insert into public.ytc_pieces (item_id, subject_id, requested_by, url, youtube_title, language, external_ref, transcription, summary, generated_content, cost, charge_key, completed_at)
    values (v_id, p_subject, p_user, p_url, p_youtube_title, p_language, p_external_ref, p_transcription, p_summary, p_generated_content, p_cost, v_key, now());
  return v_id;
end $$;
revoke execute on function public.ytc_check_kind(), public.ytc_record(uuid, uuid, text, text, text, text, text, text, jsonb, integer) from public, anon, authenticated;

alter table public.ytc_pieces enable row level security;
create policy ytc_pieces_select on public.ytc_pieces for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.ytc_pieces');
grant select on public.ytc_pieces to authenticated;
