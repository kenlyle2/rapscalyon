-- text-to-speech: Text-to-speech clips (the BuilderKit text_to_speech table) as a child of item-tracker: title, text, model, voice and an audio key, recorded once by the server with an optional core charge in the same transaction.
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.tts_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '^[A-Za-z0-9_./-]{1,255}$' or e ~ '\.\.');
$$;
revoke execute on function public.tts_valid_keys(text[], integer) from public, anon, authenticated;

create table public.tts_clips (
  item_id        uuid primary key,
  subject_id     uuid not null references public.subjects(id) on delete cascade,
  requested_by   uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(title) between 1 and 200),
  content text not null check (length(content) between 1 and 20000),
  model text not null check (length(model) between 1 and 100),
  voice text not null check (length(voice) between 1 and 100),
  external_ref   text unique check (external_ref is null or length(external_ref) <= 200),
  audio_key text not null check (audio_key ~ '^[A-Za-z0-9_./-]{1,255}$' and audio_key !~ '\.\.'),
  cost           integer not null default 0 check (cost >= 0),
  charge_key     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz,
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index tts_clips_item_subject_idx on public.tts_clips (item_id, subject_id);
create index tts_clips_subject_created_idx on public.tts_clips (subject_id, created_at desc);
create index tts_clips_requested_by_idx on public.tts_clips (requested_by);

create function public.tts_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'speech_clip') then
    raise exception 'tts_clips requires an item of kind speech_clip' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger tts_clips_kind before insert on public.tts_clips for each row execute function public.tts_check_kind();


-- Records one finished item made by an outside service (the generation happens in the app server or an agent, never in the database).
-- Idempotent on p_external_ref: a replay returns the same item. p_cost > 0 charges core credits in the same transaction (refused with 53400 when short).
create function public.tts_record(p_subject uuid, p_user uuid, p_external_ref text, p_title text, p_content text, p_model text, p_voice text, p_audio_key text, p_cost integer default 0) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid; v_res jsonb; v_key text;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  if p_cost is null or p_cost < 0 then raise exception 'invalid cost' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('tts:' || p_external_ref, 0));
  select item_id into v_existing from public.tts_clips where external_ref = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  if p_cost > 0 then
    v_key := 'tts:' || v_id;
    v_res := public.charge_credits(p_user, p_cost, v_key, 'tts.generate', 'tts_clips', v_id);
    if coalesce((v_res->>'success')::boolean, false) is not true then
      raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
    end if;
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'speech_clip', left(coalesce(p_title, 'Speech clip'), 200), 'tts');
  insert into public.tts_clips (item_id, subject_id, requested_by, title, content, model, voice, external_ref, audio_key, cost, charge_key, completed_at)
    values (v_id, p_subject, p_user, p_title, p_content, p_model, p_voice, p_external_ref, p_audio_key, p_cost, v_key, now());
  return v_id;
end $$;
revoke execute on function public.tts_check_kind(), public.tts_record(uuid, uuid, text, text, text, text, text, text, integer) from public, anon, authenticated;

alter table public.tts_clips enable row level security;
create policy tts_clips_select on public.tts_clips for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.tts_clips');
grant select on public.tts_clips to authenticated;
