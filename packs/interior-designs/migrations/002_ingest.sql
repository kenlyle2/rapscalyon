-- Functions for the ingest API (server-side only, service role). The API authenticates the caller with a shared secret and receives
-- the user's email from Pickaxe's runtime; these two functions turn that email into a user and a space (a subject) to record into.

-- Verified accounts only: an unconfirmed email never resolves, so nobody can claim an account by registering the same address elsewhere.
create function public.idg_resolve_user(p_email text) returns uuid
language sql security definer stable set search_path = '' as $$
  select u.id from auth.users u
  where lower(u.email) = lower(btrim(p_email)) and u.email_confirmed_at is not null and u.banned_until is null
  limit 1
$$;

-- The user's space for designs. With a name: the user's own subject of that name (case-insensitive), created if it does not exist.
-- Without a name: the user's oldest subject, created ('My designs', individual) if the user has none. Owned subjects only: being an
-- accepted member of someone else's subject never makes it a default. Plan limits on subject creation still apply (53400).
create function public.idg_ensure_subject(p_user uuid, p_name text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_name text := nullif(btrim(coalesce(p_name, '')), ''); v_id uuid;
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'unknown user' using errcode = '22023';
  end if;
  if v_name is not null and length(v_name) > 200 then raise exception 'space name too long' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('idg_subject:' || p_user::text, 0));
  if v_name is null then
    select id into v_id from public.subjects where owner_id = p_user order by created_at, id limit 1;
  else
    select id into v_id from public.subjects where owner_id = p_user and lower(name) = lower(v_name) order by created_at, id limit 1;
  end if;
  if v_id is null then
    insert into public.subjects (owner_id, kind, name) values (p_user, 'individual', coalesce(v_name, 'My designs')) returning id into v_id;
  end if;
  return v_id;
end $$;

revoke execute on function public.idg_resolve_user(text), public.idg_ensure_subject(uuid, text) from public, anon, authenticated;
