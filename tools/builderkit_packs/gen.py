#!/usr/bin/env python3
"""Render RapScalYon commercial packs for the BuilderKit apps from small specs.
Written against the app schemas (generated types), never from BuilderKit source code."""
import os, sys, textwrap

OUT = os.path.expanduser(os.environ.get("BUILDERKIT_OUT", "./out"))
KEYRE = "^[A-Za-z0-9_./-]{1,255}$"

def q(s): return s.replace("'", "''")

class Col:
    def __init__(self, name, kind, lo=1, hi=200, req=True, sample=None, default=None, ref=None):
        self.name, self.kind, self.lo, self.hi, self.req, self.sample, self.default, self.ref = name, kind, lo, hi, req, sample, default, ref
    @property
    def ptype(self):
        return {"text": "text", "key": "text", "keys": "text[]", "int": "integer", "num": "numeric", "jsonb": "jsonb", "bool": "boolean", "ts": "timestamptz", "ref": "uuid"}[self.kind]
    def ddl(self, P):
        nn = " not null" if self.req else ""
        if self.kind == "text": return f"{self.name} text{nn} check (length({self.name}) between {self.lo} and {self.hi})"
        if self.kind == "key": return f"{self.name} text{nn} check ({self.name} ~ '{KEYRE}' and {self.name} !~ '\\.\\.')"
        if self.kind == "keys": return f"{self.name} text[] not null default '{{}}' check ({P}_valid_keys({self.name}, {self.hi}))"
        if self.kind == "int": return f"{self.name} integer{nn} check ({self.name} between {self.lo} and {self.hi})"
        if self.kind == "num": return f"{self.name} numeric{nn} check ({self.name} between {self.lo} and {self.hi})"
        if self.kind == "jsonb": return f"{self.name} jsonb{nn} check (pg_column_size({self.name}) <= {self.hi})"
        if self.kind == "bool": return f"{self.name} boolean{nn}" + (f" default {self.default}" if self.default else "")
        if self.kind == "ts": return f"{self.name} timestamptz{nn}"
        if self.kind == "ref": return f"{self.name} uuid{nn}"
    def lit(self):
        if self.sample is not None: return self.sample
        return {"text": "'sample text'", "key": "'in/a/file.bin'", "keys": "array['out/a/1.bin']", "int": str(self.lo), "num": str(self.lo), "jsonb": "'{\"a\":1}'::jsonb", "bool": "true", "ts": "now()"}[self.kind]

class Entity:
    """One table, one item kind. mode 'job' = queued/processing/succeeded/failed lifecycle; 'record' = recorded once, already finished."""
    def __init__(self, table, fp, kind, mode, ins, outs=(), outkeys=None, title="left(p_prompt, 200)", op=None, op_label=None, unique_subject=False, ref_table=None, noun="item"):
        self.table, self.fp, self.kind, self.mode, self.ins, self.outs, self.outkeys = table, fp, kind, mode, list(ins), list(outs), outkeys
        self.title, self.op, self.op_label, self.unique_subject, self.noun = title, op, op_label, unique_subject, noun

class Pack:
    def __init__(self, name, prefix, title, tagline, who, gets, works, hood, desc, ents, requires=("item-tracker",), extra_docs="", words=""):
        self.__dict__.update(locals())

def sig(types): return ", ".join(types)

def entity_sql(P, e, parents):
    T = e.table; fp = e.fp; ins = e.ins; outs = e.outs
    job = e.mode == "job"
    lines = []
    ref = [c for c in ins if c.kind == "ref"]
    cols = []
    cols.append("item_id        uuid primary key")
    cols.append("subject_id     uuid not null references public.subjects(id) on delete cascade")
    cols.append("requested_by   uuid not null references public.profiles(id) on delete cascade")
    for c in ins: cols.append(c.ddl(P))
    if job:
        cols.append("prediction_id  text unique check (prediction_id is null or length(prediction_id) <= 200)")
        cols.append("status         text not null default 'queued' check (status in ('queued','processing','succeeded','failed'))")
        cols.append("error          text check (error is null or length(error) <= 2000)")
        if e.outkeys: cols.append(f"output_keys    text[] not null default '{{}}' check ({P}_valid_keys(output_keys, {e.outkeys}))")
    else:
        cols.append("external_ref   text unique check (external_ref is null or length(external_ref) <= 200)")
        if e.outkeys: cols.append(f"output_keys    text[] not null default '{{}}' check ({P}_valid_keys(output_keys, {e.outkeys}))")
    for c in outs: cols.append(c.ddl(P))
    cols.append("cost           integer not null default 0 check (cost >= 0)")
    cols.append("charge_key     text")
    cols.append("created_at     timestamptz not null default now()")
    cols.append("completed_at   timestamptz")
    cols.append("foreign key (item_id, subject_id) references public.it_items (id, subject_id) on delete cascade")
    for c in ref:
        pt = c.ref
        cols.append(f"foreign key ({c.name}, subject_id) references public.{pt} (item_id, subject_id) on delete restrict")
    if e.unique_subject: cols.append("unique (item_id, subject_id)")
    lines.append(f"create table public.{T} (\n  " + ",\n  ".join(cols) + "\n);")
    lines.append(f"create index {T}_item_subject_idx on public.{T} (item_id, subject_id);")
    if job: lines.append(f"create index {T}_subject_status_idx on public.{T} (subject_id, status, created_at desc);")
    else: lines.append(f"create index {T}_subject_created_idx on public.{T} (subject_id, created_at desc);")
    lines.append(f"create index {T}_requested_by_idx on public.{T} (requested_by);")
    for c in ref: lines.append(f"create index {T}_{c.name}_idx on public.{T} ({c.name}, subject_id);")
    lines.append(f"""
create function public.{fp}_check_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.it_items i where i.id = new.item_id and i.kind = '{e.kind}') then
    raise exception '{T} requires an item of kind {e.kind}' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger {T}_kind before insert on public.{T} for each row execute function public.{fp}_check_kind();
""")
    inparams = ", ".join(f"p_{c.name} {c.ptype}" for c in ins)
    incols = ", ".join(c.name for c in ins)
    invals = ", ".join(f"p_{c.name}" for c in ins)
    refcheck = ""
    for c in ref:
        refcheck += f"""  if not exists (select 1 from public.{c.ref} r where r.item_id = p_{c.name} and r.subject_id = p_subject and r.status = 'succeeded') then
    raise exception '{c.name} is not a finished item of this subject' using errcode = '23514';
  end if;
"""
    revoke_exec = [f"public.{fp}_check_kind()"]
    grant_client = None
    if job:
        outparams = (", p_keys text[]" if e.outkeys else "") + "".join(f", p_{c.name} {c.ptype}" for c in outs)
        outtypes = (["text[]"] if e.outkeys else []) + [c.ptype for c in outs]
        setout = (", output_keys = coalesce(p_keys, '{}')" if e.outkeys else "") + "".join(f", {c.name} = p_{c.name}" for c in outs)
        itypes = [c.ptype for c in ins]
        lines.append(f"""
-- Client entry point. Charges first (idempotent key per item), so a failed charge creates nothing.
create function public.{fp}_request(p_subject uuid{', ' if ins else ''}{inparams}) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_cost integer; v_key text; v_res jsonb;
begin
  if v_user is null or not public.has_subject_access(p_subject) or not public.session_satisfies_mfa() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
{refcheck}  select coalesce((select credit_cost from public.operation_pricing where operation = '{e.op}'), 1) into v_cost;
  v_key := '{fp}:' || v_id;
  v_res := public.charge_credits(v_user, v_cost, v_key, '{e.op}', '{T}', v_id);
  if coalesce((v_res->>'success')::boolean, false) is not true then
    raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, '{e.kind}', left(coalesce({e.title}, '{e.noun}'), 200), '{P}');
  insert into public.{T} (item_id, subject_id, requested_by{', ' if ins else ''}{incols}, cost, charge_key)
    values (v_id, p_subject, v_user{', ' if ins else ''}{invals}, v_cost, v_key);
  return v_id;
end $$;

-- Executor functions: service role only. Each moves a job forward once; a replayed webhook returns false.
create function public.{fp}_mark_started(p_item uuid, p_prediction_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.{T} set status = 'processing', prediction_id = p_prediction_id where item_id = p_item and status = 'queued';
  return found;
end $$;

create function public.{fp}_complete(p_item uuid{outparams}) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.{T} set status = 'succeeded', error = null, completed_at = now(){setout}
    where item_id = p_item and status in ('queued','processing');
  if found then perform public.it_log_event(p_item, 'system', 'generation succeeded'); end if;
  return found;
end $$;

-- Failure refunds the charge once (the refund key is derived from the charge key, so replays are no-ops).
create function public.{fp}_fail(p_item uuid, p_error text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare d public.{T}%rowtype;
begin
  update public.{T} set status = 'failed', error = left(p_error, 2000), completed_at = now()
    where item_id = p_item and status in ('queued','processing') returning * into d;
  if not found then return false; end if;
  if d.cost > 0 then perform public.charge_credits(d.requested_by, -d.cost, d.charge_key || ':refund', '{e.op}', '{T}', d.item_id); end if;
  perform public.it_log_event(p_item, 'system', 'generation failed, credits refunded');
  return true;
end $$;

-- Records a finished item made outside core (for example by a Pickaxe agent), with no core charge: the external system's ledger is authoritative.
-- Idempotent on p_external_ref (stored as prediction_id): a replay returns the same item. Output files must already be copied into our own storage (keys only).
create function public.{fp}_record(p_subject uuid, p_user uuid, p_external_ref text{', ' if ins else ''}{inparams}{outparams}) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('{fp}:' || p_external_ref, 0));
  select item_id into v_existing from public.{T} where prediction_id = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
{refcheck}  v_id := gen_random_uuid();
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, '{e.kind}', left(coalesce({e.title}, '{e.noun}'), 200), '{P}');
  insert into public.{T} (item_id, subject_id, requested_by{', ' if ins else ''}{incols}, prediction_id, status{', output_keys' if e.outkeys else ''}{''.join(', ' + c.name for c in outs)}, cost, completed_at)
    values (v_id, p_subject, p_user{', ' if ins else ''}{invals}, p_external_ref, 'succeeded'{", coalesce(p_keys, '{}')" if e.outkeys else ''}{''.join(', p_' + c.name for c in outs)}, 0, now());
  return v_id;
end $$;""")
        s_req = f"public.{fp}_request(uuid{', ' if ins else ''}{sig(itypes)})"
        s_start = f"public.{fp}_mark_started(uuid, text)"
        s_comp = f"public.{fp}_complete(uuid{', ' if outtypes else ''}{sig(outtypes)})"
        s_fail = f"public.{fp}_fail(uuid, text)"
        s_rec = f"public.{fp}_record(uuid, uuid, text{', ' if ins else ''}{sig(itypes)}{', ' if outtypes else ''}{sig(outtypes)})"
        revoke_exec += [s_start, s_comp, s_fail, s_rec]
        grant_client = (s_req, "request")
        e.sigs = dict(req=s_req, start=s_start, comp=s_comp, fail=s_fail, rec=s_rec, check=f"public.{fp}_check_kind()")
        e.funcs = [f"{fp}_check_kind", f"{fp}_request", f"{fp}_mark_started", f"{fp}_complete", f"{fp}_fail", f"{fp}_record"]
        e.api = [f"{fp}_request"]
    else:
        outparams = (", p_keys text[]" if e.outkeys else "") + "".join(f", p_{c.name} {c.ptype}" for c in outs)
        outtypes = (["text[]"] if e.outkeys else []) + [c.ptype for c in outs]
        itypes = [c.ptype for c in ins]
        lines.append(f"""
-- Records one finished item made by an outside service (the generation happens in the app server or an agent, never in the database).
-- Idempotent on p_external_ref: a replay returns the same item. p_cost > 0 charges core credits in the same transaction (refused with 53400 when short).
create function public.{fp}_record(p_subject uuid, p_user uuid, p_external_ref text{', ' if ins else ''}{inparams}{outparams}, p_cost integer default 0) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_existing uuid; v_res jsonb; v_key text;
begin
  if p_external_ref is null or length(p_external_ref) not between 1 and 200 then raise exception 'external ref required' using errcode = '22023'; end if;
  if p_cost is null or p_cost < 0 then raise exception 'invalid cost' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('{fp}:' || p_external_ref, 0));
  select item_id into v_existing from public.{T} where external_ref = p_external_ref;
  if found then return v_existing; end if;
  if not exists (select 1 from public.subjects s where s.id = p_subject and (s.owner_id = p_user or exists (select 1 from public.subject_members m where m.subject_id = s.id and m.user_id = p_user and m.accepted_at is not null))) then
    raise exception 'user has no access to subject' using errcode = '42501';
  end if;
  v_id := gen_random_uuid();
  if p_cost > 0 then
    v_key := '{fp}:' || v_id;
    v_res := public.charge_credits(p_user, p_cost, v_key, '{e.op}', '{T}', v_id);
    if coalesce((v_res->>'success')::boolean, false) is not true then
      raise exception 'credits: %', coalesce(v_res->>'error', 'CHARGE_FAILED') using errcode = '53400';
    end if;
  end if;
  insert into public.it_items (id, subject_id, kind, title, source) values (v_id, p_subject, '{e.kind}', left(coalesce({e.title}, '{e.noun}'), 200), '{P}');
  insert into public.{T} (item_id, subject_id, requested_by{', ' if ins else ''}{incols}, external_ref{', output_keys' if e.outkeys else ''}{''.join(', ' + c.name for c in outs)}, cost, charge_key, completed_at)
    values (v_id, p_subject, p_user{', ' if ins else ''}{invals}, p_external_ref{", coalesce(p_keys, '{}')" if e.outkeys else ''}{''.join(', p_' + c.name for c in outs)}, p_cost, v_key, now());
  return v_id;
end $$;""")
        s_rec = f"public.{fp}_record(uuid, uuid, text{', ' if ins else ''}{sig(itypes)}{', ' if outtypes else ''}{sig(outtypes)}, integer)"
        revoke_exec += [s_rec]
        e.sigs = dict(rec=s_rec, check=f"public.{fp}_check_kind()")
        e.funcs = [f"{fp}_check_kind", f"{fp}_record"]
        e.api = []
    lines.append(f"revoke execute on function {', '.join(revoke_exec)} from public, anon, authenticated;")
    if grant_client:
        lines.append(f"revoke execute on function {grant_client[0]} from public, anon;\ngrant execute on function {grant_client[0]} to authenticated;")
    lines.append(f"""
alter table public.{T} enable row level security;
create policy {T}_select on public.{T} for select to authenticated using ((select public.has_subject_access(subject_id)));
select public.apply_mfa_gate('public.{T}');
grant select on public.{T} to authenticated;""")
    return "\n".join(lines)

def migration(p):
    P = p.prefix
    head = f"""-- {p.name}: {p.desc}
-- Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.
-- Clients never write these tables. Server-side functions (service role) record results; the database makes every step idempotent.
create function public.{P}_valid_keys(k text[], max_n integer) returns boolean
language sql immutable set search_path = '' as $$
  select k is not null and cardinality(k) <= max_n
    and not exists (select 1 from unnest(k) e where e is null or e !~ '{KEYRE}' or e ~ '\\.\\.');
$$;
revoke execute on function public.{P}_valid_keys(text[], integer) from public, anon, authenticated;
"""
    parts = [head]
    for e in p.ents: parts.append(entity_sql(P, e, p.ents))
    return "\n".join(parts) + "\n"

def rollback(p):
    out = []
    for e in reversed(p.ents):
        out.append(f"drop table if exists public.{e.table};")
        for k, s in e.sigs.items(): out.append(f"drop function if exists {s};")
    for e in p.ents: out.append(f"delete from public.it_items where kind = '{e.kind}';")
    out.append(f"drop function if exists public.{p.prefix}_valid_keys(text[], integer);")
    return "\n".join(out) + "\n"

def call(fp, name, args):
    return f"public.{fp}_{name}(" + ", ".join(args) + ")"

def sample_args(cols): return [c.lit() for c in cols]

def test_sql(p):
    P = p.prefix
    B = []
    B.append(f"-- Suite for {p.name} 0.1.0.\nbegin;\ndo $$\ndeclare a uuid; b uuid; s uuid; d uuid; d2 uuid; m uuid;\nbegin")
    B.append(f"  a := t.make_user('{P}-a@example.test'); b := t.make_user('{P}-b@example.test');")
    B.append("  perform t.as_user(a);\n  insert into public.subjects (owner_id, kind, name) values (a, 'individual', 'Me') returning id into s;")
    ents = p.ents
    ref_item = {}
    for e in ents:
        T, fp = e.table, e.fp
        ins = e.ins
        def argl(subs=None, extra_pre=None):
            res = []
            for c in ins:
                if c.kind == "ref": res.append(f"'{{{c.name}}}'")
                else: res.append(c.lit())
            return res
        # resolve ref column values at runtime by concatenation helpers
        def lit_for(c, ref_var, quoted):
            if c.kind == "ref": return ("''' || " + ref_var + " || '''") if quoted else f"'{{ref}}'"
            return c.lit()
        refcols = [c for c in ins if c.kind == "ref"]
        refvar = "m"
        def direct_args(overrides=None):
            r = []
            for c in ins:
                if overrides and c.name in overrides: r.append(overrides[c.name]); continue
                r.append(refvar if c.kind == "ref" else c.lit())
            return r
        def quoted_args(overrides=None):
            r = []
            for c in ins:
                if overrides and c.name in overrides: r.append(q(overrides[c.name])); continue
                r.append("''' || m || '''" if c.kind == "ref" else q(c.lit()))
            return r
        outs = e.outs
        o_keys = ["array['out/a/1.bin']"] if e.outkeys else []
        o_cols = [c.lit() for c in outs]
        o_all = o_keys + o_cols
        o_other = (["array['out/a/other.bin']"] if e.outkeys else []) + o_cols
        keycol = next((c for c in ins if c.kind == "key"), None)
        # ---- request path (jobs)
        if e.mode == "job":
            B.append(f"  -- {T}")
            B.append("  perform t.as_user(a);")
            B.append(f"  d := {call(fp,'request',['s']+direct_args())};")
            B.append(f"  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''{e.kind}''') = 1, 'request creates the base item');")
            B.append(f"  perform t.assert((select status = 'queued' and cost >= 0 from public.{T} where item_id = d), 'job starts queued with its cost');")
            B.append(f"  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''{fp}:' || d || ''' and amount > 0') = 1, 'credits charged at request time');")
            B.append(f"  perform t.assert(t.denied('update public.{T} set status = ''succeeded'' where item_id = ''' || d || ''''), 'clients cannot update jobs');")
            B.append(f"  perform t.assert(t.denied('delete from public.{T} where item_id = ''' || d || ''''), 'clients cannot delete jobs');")
            if keycol:
                ov = {keycol.name: "'../etc/passwd'"}
                ql = ["''' || s || '''"] + quoted_args(ov)
                B.append(f"  perform t.assert(t.denied('select {call(fp,'request',ql)}'), 'key traversal refused');")
            B.append(f"  perform t.assert(t.denied('select public.{fp}_mark_started(''' || d || ''', ''p1'')'), 'users cannot call executor functions');")
            B.append(f"  perform t.assert(t.denied('select public.{fp}_fail(''' || d || ''', ''x'')'), 'users cannot fail jobs');")
            B.append("  perform t.as_service();")
            B.append(f"  perform t.assert(public.{fp}_mark_started(d, 'pred-1'), 'start moves queued to processing');")
            B.append(f"  perform t.assert(not public.{fp}_mark_started(d, 'pred-2'), 'a second start is a no-op');")
            B.append(f"  perform t.assert({call(fp,'complete',['d']+o_all)}, 'complete succeeds once');")
            B.append(f"  perform t.assert(not {call(fp,'complete',['d']+o_other)}, 'a replayed completion changes nothing');")
            B.append(f"  perform t.assert(not public.{fp}_fail(d, 'late failure'), 'a finished job cannot be failed or refunded');")
            if e.outkeys: B.append(f"  perform t.assert((select output_keys = array['out/a/1.bin'] from public.{T} where item_id = d), 'result keys stored');")
            B.append("  perform t.as_user(a);")
            B.append(f"  d2 := {call(fp,'request',['s']+direct_args())};")
            B.append("  perform t.as_service();")
            B.append(f"  perform t.assert(public.{fp}_fail(d2, 'model error'), 'fail marks the job failed');")
            B.append(f"  perform t.assert(not public.{fp}_fail(d2, 'model error again'), 'a replayed failure is a no-op');")
            B.append(f"  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''{fp}:' || d2 || ':refund''') = 1 or (select cost = 0 from public.{T} where item_id = d2), 'exactly one refund');")
            B.append("  perform t.as_user(a);")
            rec_call_q = f"select public.{fp}_record(''' || s || ''', ''' || a || ''', ''ext-1'', " + ", ".join(quoted_args() + [q(x) for x in o_all]) + ")"
            B.append(f"  perform t.assert(t.denied('{rec_call_q}'), 'users cannot call {fp}_record');")
            B.append("  perform t.as_service();")
            B.append(f"  d2 := {call(fp,'record',['s','a',chr(39)+'ext-1'+chr(39)]+direct_args()+o_all)};")
            B.append(f"  perform t.assert(d2 = {call(fp,'record',['s','a',chr(39)+'ext-1'+chr(39)]+direct_args()+o_all)}, 'a replayed record returns the same item');")
            B.append(f"  perform t.assert((select status = 'succeeded' and cost = 0 and charge_key is null from public.{T} where item_id = d2), 'recorded item is succeeded with no charge');")
            B.append(f"  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d2 || '''') = 0, 'no core credits touched');")
            rec_other = f"select public.{fp}_record(''' || s || ''', ''' || b || ''', ''ext-2'', " + ", ".join(quoted_args() + [q(x) for x in o_all]) + ")"
            B.append(f"  perform t.assert(t.denied('{rec_other}'), 'recording for a user without subject access is refused');")
            B.append(f"  m := d2;" if refcols is None else "")
            if any(c for c in ents if any(x.kind == 'ref' and x.ref == T for x in c.ins)):
                B.append("  m := d2;")  # remember a succeeded parent for later entities
            B.append("  perform t.as_user(b);")
            B.append(f"  perform t.assert(t.rows('select 1 from public.{T}') = 0, 'other users see no jobs');")
            ql = ["''' || s || '''"] + quoted_args()
            B.append(f"  perform t.assert(t.denied('select {call(fp,'request',ql)}'), 'cannot request into a foreign subject');")
            B.append("  perform t.as_anon();")
            B.append(f"  perform t.assert(t.denied('select 1 from public.{T}'), 'anon denied');")
            B.append(f"  perform t.assert(t.denied('select {call(fp,'request',ql)}'), 'anon cannot request');")
        else:
            B.append(f"  -- {T}")
            B.append("  perform t.as_user(a);")
            rec_q = f"select public.{fp}_record(''' || s || ''', ''' || a || ''', ''ext-1'', " + ", ".join(quoted_args() + [q(x) for x in o_all]) + ")"
            B.append(f"  perform t.assert(t.denied('{rec_q}'), 'users cannot call {fp}_record');")
            B.append("  perform t.as_service();")
            B.append(f"  d := {call(fp,'record',['s','a',chr(39)+'ext-1'+chr(39)]+direct_args()+o_all)};")
            B.append(f"  perform t.assert(d = {call(fp,'record',['s','a',chr(39)+'ext-1'+chr(39)]+direct_args()+o_all)}, 'a replayed record returns the same item');")
            B.append(f"  perform t.assert(t.rows('select 1 from public.it_items where id = ''' || d || ''' and kind = ''{e.kind}''') = 1, 'record creates the base item');")
            B.append(f"  perform t.assert((select cost = 0 and charge_key is null from public.{T} where item_id = d), 'no charge by default');")
            B.append(f"  perform t.assert(t.rows('select 1 from public.credit_usage_log where ref_id = ''' || d || '''') = 0, 'no core credits touched');")
            B.append(f"  d2 := {call(fp,'record',['s','a',chr(39)+'ext-2'+chr(39)]+direct_args()+o_all+['1'])};")
            B.append(f"  perform t.assert(t.rows('select 1 from public.credit_usage_log where idempotency_key = ''{fp}:' || d2 || ''' and amount > 0') = 1, 'a positive cost is charged in the same transaction');")
            quoted_unaff = f"select public.{fp}_record(''' || s || ''', ''' || a || ''', ''ext-3'', " + ", ".join(quoted_args() + [q(x) for x in o_all] + ["1000000000"]) + ")"
            B.append(f"  perform t.assert(t.denied('{quoted_unaff}'), 'an unaffordable cost is refused');")
            rec_other = f"select public.{fp}_record(''' || s || ''', ''' || b || ''', ''ext-4'', " + ", ".join(quoted_args() + [q(x) for x in o_all]) + ")"
            B.append(f"  perform t.assert(t.denied('{rec_other}'), 'recording for a user without subject access is refused');")
            B.append("  perform t.as_user(b);")
            B.append(f"  perform t.assert(t.rows('select 1 from public.{T}') = 0, 'other users see no records');")
            B.append("  perform t.as_anon();")
            B.append(f"  perform t.assert(t.denied('select 1 from public.{T}'), 'anon denied');")
    B.append("end $$;\nrollback;\n")
    return "\n".join(x for x in B if x)

def marketing(p):
    gets = "\n".join(f"- {g}" for g in p.gets)
    return f"""# {p.title}
> {p.tagline}

## Who it's for
{p.who}

## What you get
{gets}

## Works well with
{p.works}.

## Under the hood
{p.hood}
"""

def docs_readme(p):
    ents = "\n".join(f"- `{e.table}` (item kind `{e.kind}`): functions {', '.join('`'+f+'`' for f in e.funcs)}" for e in p.ents)
    return f"""# {p.name} (0.1.0)

{p.desc}

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.

## What is in it
{ents}

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).

{p.extra_docs}
## Replaces in the BuilderKit schema
{p.words}

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.
"""

def docs_security(p):
    return f"""# Security: {p.name}

- Clients can only read rows of their own subjects (row-level security through `has_subject_access`, plus the MFA gate). No client write grants exist on any table; writes go through SECURITY DEFINER functions with an empty search path.
- Executor and record functions are service role only (execute revoked from public, anon and authenticated), tested.
- Every record call checks that the user owns or is an accepted member of the subject, and is idempotent on an external reference.
- File and result fields hold storage keys (character allow-list, no `..`), never URLs or data URLs. Result URLs from generators expire; copy before recording.
- No provider secret or token is stored. Webhook signatures are the executor's job; the database makes every step idempotent.
- Known gaps: executor and storage policies not written, no per-subject rate limits beyond core's, not tested against real data.
"""

def toml(p):
    funcs = [f"{p.prefix}_valid_keys"] + [f for e in p.ents for f in e.funcs]
    api = [f for e in p.ents for f in e.api]
    ops = [(e.op, e.op_label) for e in p.ents if e.op]
    s = f"""[pack]
name = "{p.name}"
prefix = "{p.prefix}"
version = "0.1.0"
description = "{p.desc}"
license = "LicenseRef-RapScalYon-Commercial"
tier = "commercial"
requires_core = ">=0.1"
requires = [{", ".join(chr(34)+r+chr(34) for r in p.requires)}]
conflicts = []

[db]
tables = [{", ".join(chr(34)+e.table+chr(34) for e in p.ents)}]
functions = [{", ".join(chr(34)+f+chr(34) for f in funcs)}]
api_functions = [{", ".join(chr(34)+f+chr(34) for f in api)}]
"""
    if ops: s += "\n[credits]\noperations = [" + ", ".join(f'{{ name = "{o}", label = "{l}" }}' for o, l in ops) + "]\n"
    return s

def write(p):
    d = os.path.join(OUT, p.name)
    for sub in ("migrations", "rollback", "tests", "docs"): os.makedirs(os.path.join(d, sub), exist_ok=True)
    mig = migration(p)
    open(os.path.join(d, "pack.toml"), "w").write(toml(p))
    open(os.path.join(d, "migrations", "001_init.sql"), "w").write(mig)
    open(os.path.join(d, "rollback", "001_init.sql"), "w").write(rollback(p))
    open(os.path.join(d, "tests", "001.sql"), "w").write(test_sql(p))
    open(os.path.join(d, "docs", "MARKETING.md"), "w").write(marketing(p))
    open(os.path.join(d, "docs", "README.md"), "w").write(docs_readme(p))
    open(os.path.join(d, "docs", "SECURITY.md"), "w").write(docs_security(p))
