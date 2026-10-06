-- chat-with-youtube: BuilderKit's chat_with_youtube row (url, video_title, style, tone, transcription, summary, ingestion_done, chat_history)
-- becomes a source attached to an ai-chat conversation. The history lives in cht_messages.
create table public.cwy_sources (
  item_id         uuid primary key,
  subject_id      uuid not null references public.subjects(id) on delete cascade,
  url             text not null check (length(url) between 1 and 2000),
  video_title     text not null check (length(video_title) between 1 and 300),
  style           text check (length(style) between 1 and 60),
  tone            text check (length(tone) between 1 and 60),
  transcription   text not null check (length(transcription) between 1 and 500000),
  summary         text check (length(summary) between 1 and 50000),
  ingestion_done  boolean not null default false,
  created_at      timestamptz not null default now(),
  foreign key (item_id, subject_id) references public.cht_chats (item_id, subject_id) on delete cascade
);
create index cwy_sources_item_subject_idx on public.cwy_sources (item_id, subject_id);
create index cwy_sources_subject_idx on public.cwy_sources (subject_id);

-- Attaches the video to a chat once (service role). A replay with the same link is a no-op; a different link for the same chat is refused.
create function public.cwy_attach(p_item uuid, p_url text, p_video_title text, p_style text, p_tone text, p_transcription text, p_summary text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.cht_chats%rowtype; v_existing text;
begin
  select * into c from public.cht_chats where item_id = p_item;
  if not found then raise exception 'unknown chat' using errcode = '22023'; end if;
  select url into v_existing from public.cwy_sources where item_id = p_item;
  if found then
    if v_existing = p_url then return false; end if;
    raise exception 'chat already has a video' using errcode = '23505';
  end if;
  insert into public.cwy_sources (item_id, subject_id, url, video_title, style, tone, transcription, summary)
    values (p_item, c.subject_id, p_url, p_video_title, p_style, p_tone, p_transcription, p_summary);
  return true;
end $$;

-- Marks the transcript as indexed for retrieval (service role). Returns true only on the first call.
create function public.cwy_mark_ingested(p_item uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.cwy_sources set ingestion_done = true where item_id = p_item and not ingestion_done;
  return found;
end $$;
revoke execute on function public.cwy_attach(uuid, text, text, text, text, text, text), public.cwy_mark_ingested(uuid) from public, anon, authenticated;

alter table public.cwy_sources enable row level security;
create policy cwy_sources_select on public.cwy_sources for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.cwy_sources');
grant select on public.cwy_sources to authenticated;
