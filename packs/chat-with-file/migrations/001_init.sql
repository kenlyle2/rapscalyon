-- chat-with-file: BuilderKit's chat_with_file row (file, filename, chat_history) becomes a source attached to an ai-chat conversation.
-- The history lives in cht_messages; this table only records which file the chat is about. The file itself is a storage key, never inline.
create table public.cwf_sources (
  item_id     uuid primary key,
  subject_id  uuid not null references public.subjects(id) on delete cascade,
  file_key    text not null check (file_key ~ '^[A-Za-z0-9_./-]{1,255}$' and file_key !~ '\.\.'),
  filename    text not null check (length(filename) between 1 and 255),
  created_at  timestamptz not null default now(),
  foreign key (item_id, subject_id) references public.cht_chats (item_id, subject_id) on delete cascade
);
create index cwf_sources_item_subject_idx on public.cwf_sources (item_id, subject_id);
create index cwf_sources_subject_idx on public.cwf_sources (subject_id);

-- Attaches the file to a chat once (service role). A replay with the same key is a no-op; a different key for the same chat is refused.
create function public.cwf_attach(p_item uuid, p_file_key text, p_filename text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.cht_chats%rowtype; v_existing text;
begin
  select * into c from public.cht_chats where item_id = p_item;
  if not found then raise exception 'unknown chat' using errcode = '22023'; end if;
  select file_key into v_existing from public.cwf_sources where item_id = p_item;
  if found then
    if v_existing = p_file_key then return false; end if;
    raise exception 'chat already has a file' using errcode = '23505';
  end if;
  insert into public.cwf_sources (item_id, subject_id, file_key, filename) values (p_item, c.subject_id, p_file_key, p_filename);
  return true;
end $$;
revoke execute on function public.cwf_attach(uuid, text, text) from public, anon, authenticated;

alter table public.cwf_sources enable row level security;
create policy cwf_sources_select on public.cwf_sources for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.cwf_sources');
grant select on public.cwf_sources to authenticated;
