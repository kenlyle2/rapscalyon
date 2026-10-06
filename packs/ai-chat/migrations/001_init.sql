-- ai-chat: BuilderKit's chat tables (llamagpt, multillm_chatgpt, deepseek_chat, gemini_chat) share one shape: id, user_id, title, chat_history json.
-- Here a chat is an item of kind 'chat' (child of item-tracker) and its history is a row per message, so it can be paged, counted and capped.
-- Clients never write. The app server (service role) starts chats and appends messages; every step is idempotent on an external reference.
create table public.cht_chats (
  item_id          uuid primary key,
  subject_id       uuid not null references public.subjects(id) on delete cascade,
  requested_by     uuid not null references public.profiles(id) on delete cascade,
  provider         text not null check (length(provider) between 1 and 40),
  model            text check (length(model) between 1 and 100),
  external_ref     text unique check (external_ref is null or length(external_ref) <= 200),
  message_count    integer not null default 0 check (message_count between 0 and 5000),
  last_message_at  timestamptz,
  created_at       timestamptz not null default now(),
  unique (item_id, subject_id),
  foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade
);
create index cht_chats_item_subject_idx on public.cht_chats (item_id, subject_id);
create index cht_chats_subject_recent_idx on public.cht_chats (subject_id, last_message_at desc nulls last);
create index cht_chats_requested_by_idx on public.cht_chats (requested_by);

create table public.cht_messages (
  id            bigint generated always as identity primary key,
  item_id       uuid not null,
  subject_id    uuid not null,
  seq           integer not null check (seq between 1 and 5000),
  role          text not null check (role in ('user', 'assistant', 'system')),
  content       text not null check (length(content) between 1 and 100000),
  external_ref  text check (external_ref is null or length(external_ref) <= 200),
  cost          integer not null default 0 check (cost >= 0),
  created_at    timestamptz not null default now(),
  unique (item_id, seq),
  unique (item_id, external_ref),
  foreign key (item_id, subject_id) references public.cht_chats (item_id, subject_id) on delete cascade
);
create index cht_messages_item_subject_idx on public.cht_messages (item_id, subject_id);

create function public.cht_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = 'chat') then
    raise exception 'cht_chats requires an item of kind chat' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger cht_chats_kind before insert on public.cht_chats for each row execute function public.cht_check_kind();

-- Starts a chat for a user who owns or is an accepted member of the subject. Idempotent on p_external_ref (a replay returns the same chat).
create function public.cht_start(p_subject uuid, p_user uuid, p_provider text, p_model text, p_title text, p_external_ref text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is not null then
    perform pg_advisory_xact_lock(hashtextextended('cht:' || p_external_ref, 0));
    select item_id into v_existing from public.cht_chats where external_ref = p_external_ref;
    if found then return v_existing; end if;
  end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, 'chat', left(coalesce(nullif(p_title, ''), 'New chat'), 200), 'cht');
  insert into public.cht_chats (item_id, subject_id, requested_by, provider, model, external_ref) values (v_id, p_subject, p_user, p_provider, p_model, p_external_ref);
  return v_id;
end $$;

-- Appends one message and returns its position. Idempotent on (chat, p_external_ref). p_cost > 0 charges core credits for this message in the same
-- transaction (refused with 53400 when short); a replay never charges twice.
create function public.cht_append(p_item uuid, p_role text, p_content text, p_external_ref text default null, p_cost integer default 0) returns integer
language plpgsql security definer set search_path = '' as $$
declare c public.cht_chats%rowtype; v_seq integer; v_res jsonb;
begin
  if p_cost is null or p_cost < 0 then raise exception 'invalid cost' using errcode = '22023'; end if;
  select * into c from public.cht_chats where item_id = p_item for update;
  if not found then raise exception 'unknown chat' using errcode = '22023'; end if;
  if p_external_ref is not null then
    select seq into v_seq from public.cht_messages where item_id = p_item and external_ref = p_external_ref;
    if found then return v_seq; end if;
  end if;
  if c.message_count >= 5000 then raise exception 'chat is full' using errcode = '54000'; end if;
  v_seq := c.message_count + 1;
  if p_cost > 0 then
    v_res := public.charge_credits(c.requested_by, p_cost, 'cht:' || p_item || ':' || v_seq, 'cht.reply', 'cht_chats', p_item);
    if coalesce((v_res->>'success')::boolean, false) is not true then
      raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
    end if;
  end if;
  insert into public.cht_messages (item_id, subject_id, seq, role, content, external_ref, cost) values (p_item, c.subject_id, v_seq, p_role, p_content, p_external_ref, p_cost);
  update public.cht_chats set message_count = v_seq, last_message_at = now() where item_id = p_item;
  return v_seq;
end $$;
revoke execute on function public.cht_check_kind(), public.cht_start(uuid, uuid, text, text, text, text), public.cht_append(uuid, text, text, text, integer) from public, anon, authenticated;

alter table public.cht_chats enable row level security;
alter table public.cht_messages enable row level security;
create policy cht_chats_select on public.cht_chats for select to authenticated using ((select public.has_subject_access(subject_id)));
create policy cht_messages_select on public.cht_messages for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.cht_chats');
select public.apply_mfa_gate('public.cht_messages');
grant select on public.cht_chats, public.cht_messages to authenticated;
