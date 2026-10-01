-- Test helpers (loaded by `rapscalyon.py test`; everything lives in schema t and is rolled back by each suite).
\set ON_ERROR_STOP on
create schema if not exists t;
grant usage on schema t to public;

create or replace function t.assert(p_ok boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;

-- create a confirmed auth user (and, via trigger, its profile). Returns the id.
create or replace function t.make_user(p_email text, p_admin boolean default false, p_tier text default 'free') returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', p_email, '{}', '{}', now(), now());
  update public.profiles set is_admin = p_admin, tier = p_tier where id = v_id;
  return v_id;
end $$;

create or replace function t.as_user(p_id uuid, p_aal text default 'aal1') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('request.jwt.claim.sub', p_id::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function t.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;
create or replace function t.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;
create or replace function t.as_admin() returns void language plpgsql as $$
begin execute 'reset role'; end $$;

-- runs a statement and reports whether it was refused (privilege or RLS violation or listed sqlstate)
create or replace function t.denied(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then return true;
          when others then
            if sqlstate in ('42501', '53400', '23514', '23503', '23505') then return true; end if;
            raise;
end $$;

create or replace function t.rows(p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin execute 'select count(*) from (' || p_sql || ') s' into n; return n; end $$;

grant execute on all functions in schema t to public;
