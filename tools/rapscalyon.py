#!/usr/bin/env python3
"""RapScalYon pack installer + validator (GPL-3.0-or-later).

  rapscalyon.py pack add <dir|name> [--dry-run] [--app apps/web]
  rapscalyon.py pack remove <name>
  rapscalyon.py pack validate <dir|name>      # install in a transaction, validate, roll back
  rapscalyon.py pack list
  rapscalyon.py test [--pack name]

Environment: DATABASE_URL (default: local Supabase on :54322).
A pack is installed in ONE transaction: snapshot -> apply migrations -> catalog validation -> commit.
Any violation aborts the transaction, so a rejected pack leaves no trace.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time, tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "packs"
# Extra pack roots (os.pathsep-separated), e.g. a licensed rapscalyon-plus checkout. Searched after packs/.
EXTRA_PACKS = [Path(x).expanduser() for x in os.environ.get("RAPSCALYON_PACKS_PATH", "").split(os.pathsep) if x]

def pack_dir(name):
    for root in [PACKS, *EXTRA_PACKS]:
        if (root / name / "pack.toml").exists(): return root / name
    return PACKS / name
MIGRATIONS = ROOT / "supabase" / "migrations"
DB_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
CORE_VERSION = "0.1.0"

CORE_TABLES = ["profiles", "user_credentials", "admin_settings", "billing_events", "operation_pricing", "credit_usage_log",
               "rate_limits", "subjects", "subject_members", "app_events", "account_health_findings", "pack_migrations"]
CORE_FUNCTIONS = ["set_updated_at", "handle_new_user", "is_admin", "get_plan_limit", "get_my_limits", "charge_credits",
                  "check_rate_limit", "has_subject_access", "is_subject_owner", "session_satisfies_mfa", "apply_mfa_gate", "ensure_rls"]

SECRET_PATTERNS = [
    (r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}", "JWT-looking token"),
    (r"\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}", "payment-provider key"),
    (r"\bsb_secret_[A-Za-z0-9_-]{10,}", "Supabase secret key"),
    (r"(?i)\bbearer\s+[A-Za-z0-9._-]{20,}", "bearer token"),
    (r"(?i)(password|secret|api[_-]?key)\s*(=|:)\s*'[^']{8,}'", "inline credential"),
    (r"(?i)\bto\s+(anon|public)\b", "grant to anon/public"),
]

def die(msg, code=1):
    print(msg, file=sys.stderr); sys.exit(code)

# Production projects this tool must never touch (PostGlider, TatPlat, JobsGlider).
# Projects this tool must never touch (your production refs). Kept out of the repo: set RS_PROTECTED_REFS="ref1,ref2"
# or list one ref per line in tools/protected-refs.txt (git-ignored).
def _protected_refs():
    refs = set(filter(None, os.environ.get("RS_PROTECTED_REFS", "").replace(" ", "").split(",")))
    f = Path(__file__).resolve().parent / "protected-refs.txt"
    if f.exists(): refs |= {l.strip() for l in f.read_text().splitlines() if l.strip() and not l.startswith("#")}
    return refs
PROTECTED_REFS = _protected_refs()
REMOTE = None   # Supabase project ref when running against a hosted project (--project / RS_PROJECT)

def _remote_workdir(ref):
    """A scratch dir linked to the project; `supabase db query --linked` talks to the Management API (no DB password needed)."""
    wd = Path(tempfile.gettempdir()) / "rs-remote" / ref
    if not (wd / "supabase" / ".temp" / "project-ref").exists():
        wd.mkdir(parents=True, exist_ok=True)
        subprocess.run(["supabase", "init", "--workdir", str(wd)], capture_output=True)
        r = subprocess.run(["supabase", "link", "--project-ref", ref, "--yes", "--workdir", str(wd)], capture_output=True, text=True)
        if r.returncode: die("supabase link failed: " + (r.stderr or r.stdout))
    return wd

class _Res:
    def __init__(self, rc, out="", err=""): self.returncode, self.stdout, self.stderr = rc, out, err

def run_remote(sql):
    f = Path(tempfile.mkdtemp(prefix="rs-q-")) / "q.sql"; f.write_text(sql)
    cmd = ["supabase", "db", "query", "--linked", "--workdir", str(_remote_workdir(REMOTE)), "-f", str(f)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if "{" not in r.stdout:  # CLI transport flake (login-role init / telemetry timeout): no result came back, retry once
        time.sleep(3); r = subprocess.run(cmd, capture_output=True, text=True)
    body = r.stdout[r.stdout.find("{"):] if "{" in r.stdout else ""
    try: j = json.loads(body)
    except Exception: return _Res(r.returncode or 1, "", r.stdout + r.stderr)
    if j.get("_tag") == "Error" or r.returncode:
        msg = j.get("error", {}).get("message", body)
        try: msg = json.loads(msg[msg.index("{"):]).get("message", msg)
        except Exception: pass
        return _Res(1, "", msg)
    rows = j.get("rows", [])
    return _Res(0, "\n".join("|".join("" if v is None else str(v) for v in row.values()) for row in rows))

def strip_meta(sql):
    return "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("\\"))

def execute(script):
    """Run a whole script as ONE unit. Remote: a multi-statement request is a single implicit transaction."""
    if REMOTE: return run_remote(strip_meta(script))
    return psql(["-f", "-"], input_sql=script)

def psql(args, input_sql=None):
    return subprocess.run(["psql", DB_URL, "-X", "-q", "-v", "ON_ERROR_STOP=1", *args],
                          input=input_sql, capture_output=True, text=True)

def query(sql):
    r = run_remote(sql) if REMOTE else psql(["-At", "-c", sql])
    if r.returncode: die("query failed: " + r.stderr.strip())
    return r.stdout.strip()

def installed_packs():
    out = query("select pack || ' ' || version from public.pack_migrations group by pack, version")
    return {l.split()[0]: l.split()[1] for l in out.splitlines() if l}

def load_pack(arg):
    d = Path(arg) if Path(arg).is_dir() else pack_dir(arg)
    if not (d / "pack.toml").exists(): die(f"no pack.toml in {d}")
    with open(d / "pack.toml", "rb") as f: m = tomllib.load(f)
    p = m.get("pack", {})
    for k in ("name", "prefix", "version", "license", "requires_core"):
        if k not in p: die(f"pack.toml: [pack].{k} is required")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,40}", p["name"]): die("pack name must be kebab-case")
    if not re.fullmatch(r"[a-z]{2,6}", p["prefix"]): die("pack prefix must be 2-6 lowercase letters")
    tier = p.get("tier", "community")
    if tier not in ("official", "verified", "community", "commercial"): die("pack tier must be official, verified, community or commercial")
    if tier == "commercial":
        # Proprietary packs (the "plus" tier) are distributed outside this repo under their own licence; the installer
        # still applies every security rule. They must say so explicitly, never by accident.
        if not p["license"].startswith("LicenseRef-"): die("commercial packs must declare license = \"LicenseRef-<name>\"")
    else:
        if not p["license"].upper().startswith(("GPL", "AGPL", "LGPL", "MIT", "APACHE", "BSD")): die("unrecognised license")
        if tier in ("official", "verified") and not p["license"].upper().startswith("AGPL"): die("official/verified packs must be AGPL-licensed")
    if not (d / "docs" / "README.md").exists() or not (d / "docs" / "SECURITY.md").exists():
        die("docs/README.md and docs/SECURITY.md are required")
    mig = sorted((d / "migrations").glob("*.sql"))
    if not mig: die("pack has no migrations/*.sql")
    if not (d / "rollback").is_dir(): die("rollback/ is required")
    return d, m, mig

def static_scan(files):
    bad = []
    for f in files:
        text = f.read_text()
        for pat, what in SECRET_PATTERNS:
            for mt in re.finditer(pat, text):
                bad.append(f"{f.name}: {what}: ...{mt.group(0)[:40]}")
        if re.search(r"(?i)\bcreate\s+extension\b(?![^;]*schema\s+extensions)", text):
            bad.append(f"{f.name}: create extension must target schema extensions")
        if re.search(r"(?i)\bsecurity\s+definer\b", text) is None and re.search(r"(?i)\bexecute\s+(format\()?", text):
            pass
    return bad

def sql_list(items):
    return "array[" + ",".join("'" + i.replace("'", "''") + "'" for i in items) + "]::text[]" if items else "array[]::text[]"

FP_SQL = f"""
select md5(coalesce(string_agg(x, E'\\n' order by x), '')) fp from (
  select 'col:'||table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'') x
    from information_schema.columns where table_schema='public' and table_name = any({sql_list(CORE_TABLES)})
  union all select 'pol:'||tablename||'.'||policyname||':'||permissive||':'||cmd||':'||coalesce(qual,'')||':'||coalesce(with_check,'')||':'||roles::text
    from pg_policies where schemaname='public' and tablename = any({sql_list(CORE_TABLES)})
  union all select 'fn:'||p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,'')
    from pg_proc p where pronamespace='public'::regnamespace and proname = any({sql_list(CORE_FUNCTIONS)})
  union all select 'acl:'||c.relname||':'||coalesce(c.relacl::text,'')||':'||c.relrowsecurity::text
    from pg_class c where relnamespace='public'::regnamespace and relname = any({sql_list(CORE_TABLES)})
  union all select 'att:'||c.relname||'.'||a.attname||':'||coalesce(a.attacl::text,'')
    from pg_attribute a join pg_class c on c.oid=a.attrelid
   where c.relnamespace='public'::regnamespace and c.relname = any({sql_list(CORE_TABLES)}) and a.attnum>0 and not a.attisdropped
  union all select 'con:'||conrelid::regclass::text||':'||conname||':'||pg_get_constraintdef(oid)
    from pg_constraint where conrelid in (select oid from pg_class where relnamespace='public'::regnamespace and relname = any({sql_list(CORE_TABLES)}))
) s"""

SNAPSHOT_SQL = f"""
create temp table rs_before as
  select 'rel'::text kind, c.relname::text name from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p','v','m')
  union all select 'fn', p.oid::regprocedure::text from pg_proc p where p.pronamespace='public'::regnamespace;
create temp table rs_fp_before as {FP_SQL};
"""

VALIDATE_SQL = r"""
do $rs$
declare
  v text[] := '{}';
  pfx text := current_setting('rs.prefix');
  refs text[] := string_to_array(nullif(current_setting('rs.reference_tables'), ''), ',');
  apis text[] := string_to_array(nullif(current_setting('rs.api_functions'), ''), ',');
  r record; pr record; kr record;
  fp_after text;
begin
  -- 1 core untouched
  execute $q$ select fp from ( __FP__ ) z $q$ into fp_after;
  if fp_after is distinct from (select fp from rs_fp_before) then
    v := v || 'core objects were modified (columns, policies, functions, constraints or grants on core tables changed)'::text;
  end if;

  for r in
    select c.oid, c.relname::text rel, c.relkind, c.relrowsecurity, c.reloptions
      from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p','v','m')
       and not exists (select 1 from rs_before b where b.kind = 'rel' and b.name = c.relname::text)
  loop
    -- 2 naming
    if r.rel not like pfx || '\_%' then v := v || format('%s: name must start with "%s_"', r.rel, pfx); end if;

    if r.relkind in ('v','m') then
      if r.relkind = 'v' and not coalesce(r.reloptions @> array['security_invoker=true'] or r.reloptions @> array['security_invoker=on'], false) then
        v := v || format('%s: view must be security_invoker', r.rel);
      end if;
      if r.relkind = 'm' and (has_any_column_privilege('anon', r.oid, 'select') or has_any_column_privilege('authenticated', r.oid, 'select')) then
        v := v || format('%s: materialized view must not be exposed to API roles', r.rel);
      end if;
      continue;
    end if;

    -- 3 RLS
    if not r.relrowsecurity then v := v || format('%s: row level security is off', r.rel); end if;

    -- 4 privileges
    if has_any_column_privilege('anon', r.oid, 'select,insert,update,references') or has_table_privilege('anon', r.oid, 'delete,truncate,trigger') then
      v := v || format('%s: anon holds privileges', r.rel);
    end if;
    if has_table_privilege('authenticated', r.oid, 'update') then v := v || format('%s: authenticated has table-level UPDATE (use a column list)', r.rel); end if;
    if has_table_privilege('authenticated', r.oid, 'insert') then v := v || format('%s: authenticated has table-level INSERT (use a column list)', r.rel); end if;
    if has_table_privilege('authenticated', r.oid, 'truncate,references,trigger') then v := v || format('%s: authenticated has TRUNCATE/REFERENCES/TRIGGER', r.rel); end if;

    -- 5 policies that grant everything
    if not (r.rel = any(coalesce(refs, '{}'))) then
      for pr in select polname, pg_get_expr(polqual, polrelid) q, pg_get_expr(polwithcheck, polrelid) w
                 from pg_policy where polrelid = r.oid and polpermissive loop
        if pr.q = 'true' or pr.w = 'true' then
          v := v || format('policy %s on %s: USING/WITH CHECK (true) on a non-reference table', pr.polname, r.rel);
        end if;
      end loop;
    end if;
  end loop;

  -- re-iterate tables for checks that need the table row (loop var was reused above)
  for r in
    select c.oid, c.relname::text rel
      from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
       and not exists (select 1 from rs_before b where b.kind = 'rel' and b.name = c.relname::text)
  loop
    -- 6 ownership chain
    if not (r.rel = any(coalesce(refs, '{}'))) and not exists (
         select 1 from pg_constraint k
          where k.conrelid = r.oid and k.contype = 'f'
            and (k.confrelid in ('public.profiles'::regclass, 'public.subjects'::regclass, 'auth.users'::regclass)
                 or exists (select 1 from pg_class t where t.oid = k.confrelid and t.relnamespace = 'public'::regnamespace
                              and not exists (select 1 from rs_before b where b.kind = 'rel' and b.name = t.relname::text)))) then
      v := v || format('%s: no foreign key to profiles/subjects (or another pack table), so rows have no owner', r.rel);
    end if;
    -- 7 MFA gate when API roles can touch it
    if has_any_column_privilege('authenticated', r.oid, 'select,insert,update') or has_table_privilege('authenticated', r.oid, 'delete') then
      if not exists (select 1 from pg_policy p where p.polrelid = r.oid and not p.polpermissive and p.polname = 'require_mfa_when_enrolled') then
        v := v || format('%s: missing the require_mfa_when_enrolled restrictive policy (call public.apply_mfa_gate)', r.rel);
      end if;
      if not exists (select 1 from pg_policy p where p.polrelid = r.oid and p.polpermissive) then
        v := v || format('%s: API roles have grants but no permissive policy (dead grants)', r.rel);
      end if;
    end if;
    -- 8 every FK has a supporting index
    for kr in select k.conname, k.conkey from pg_constraint k where k.conrelid = r.oid and k.contype = 'f'
              and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and (i.indkey::int2[])[0:array_length(k.conkey,1)-1] <@ k.conkey and k.conkey <@ (i.indkey::int2[])[0:array_length(k.conkey,1)-1]) loop
      v := v || format('%s: foreign key %s has no index starting with all of its columns', r.rel, kr.conname);
    end loop;
  end loop;

  -- 9 functions
  for r in
    select p.oid, p.proname::text fname, p.oid::regprocedure::text sig, p.prosecdef, p.proconfig, p.prosrc, p.prorettype::regtype::text rettype,
           exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE') pub_exec
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and not exists (select 1 from rs_before b where b.kind = 'fn' and b.name = p.oid::regprocedure::text)
  loop
    if r.fname not like pfx || '\_%' then v := v || format('function %s: name must start with "%s_"', r.sig, pfx); end if;
    if not coalesce(r.proconfig @> array['search_path=""'], false) then v := v || format('function %s: must set search_path = ''''', r.sig); end if;
    if r.pub_exec or has_function_privilege('anon', r.oid, 'execute') then v := v || format('function %s: executable by PUBLIC/anon', r.sig); end if;
    if has_function_privilege('authenticated', r.oid, 'execute') then
      if not (r.fname = any(coalesce(apis, '{}'))) then
        v := v || format('function %s: executable by authenticated but not declared in [db].api_functions', r.sig);
      elsif r.prosecdef and r.prosrc !~ 'auth\.uid\(\)' and r.prosrc !~ 'has_subject_access|is_subject_owner|is_admin\(' then
        v := v || format('function %s: SECURITY DEFINER callable by users but never checks the caller (auth.uid / has_subject_access / is_admin)', r.sig);
      end if;
    end if;
  end loop;

  if array_length(v, 1) > 0 then
    raise exception E'RS_VALIDATION\n%', array_to_string(v, E'\n');
  end if;
end $rs$;
""".replace("__FP__", FP_SQL)


def build_script(pack_dir, manifest, mig_files, dry_run, write_dir=None):
    p = manifest["pack"]; db = manifest.get("db", {})
    lines = ["\\set ON_ERROR_STOP on", "begin;",
             f"select set_config('rs.prefix', '{p['prefix']}', true), set_config('rs.reference_tables', '{','.join(db.get('reference_tables', []))}', true), "
             f"set_config('rs.api_functions', '{','.join(db.get('api_functions', []))}', true);",
             SNAPSHOT_SQL]
    for f in mig_files:
        lines.append(f"\\echo applying {f.name}")
        lines.append(f.read_text() if REMOTE else f"\\i {f}")
    lines.append(VALIDATE_SQL)
    lines.append("rollback;" if dry_run else "commit;")
    return "\n".join(lines)

def with_registry(f, pack, version):
    text = f.read_text()
    sha = hashlib.sha256(text.encode()).hexdigest()
    return text.rstrip("\n") + (f"\n\ninsert into public.pack_migrations (pack, version, filename, checksum) "
                                f"values ('{pack}', '{version}', '{f.name}', '{sha}') on conflict (pack, filename) do nothing;\n"), sha

def cmd_add(args, dry_override=None):
    dry = args.dry_run if dry_override is None else dry_override
    d, m, mig = load_pack(args.pack)
    p = m["pack"]
    have = installed_packs()
    core = query("select setting_value #>> '{}' from public.admin_settings where setting_key = 'core_version'") or CORE_VERSION
    if tuple(map(int, core.split("."))) < tuple(map(int, re.sub(r"[^0-9.]", "", p["requires_core"]).split("."))) :
        die(f"pack needs core {p['requires_core']}, database has {core}")
    for dep in p.get("requires", []):
        if dep not in have: die(f"requires pack '{dep}' which is not installed")
    for c in p.get("conflicts", []):
        if c in have: die(f"conflicts with installed pack '{c}'")
    scan = static_scan(mig)
    if scan: die("static scan rejected the pack:\n  " + "\n  ".join(scan))

    tmp = Path(tempfile.mkdtemp(prefix="rs-pack-"))
    applied = []
    pending = []
    already = set(query(f"select filename from public.pack_migrations where pack = '{p['name']}'").splitlines())
    for f in mig:
        if f.name in already: continue
        text, sha = with_registry(f, p["name"], p["version"])
        out = tmp / f.name; out.write_text(text); pending.append((f, out))
    if not pending:
        print(f"{p['name']} {p['version']}: already installed, nothing to apply")
        if args.app and not dry: app_install(d, m, Path(args.app))  # still sync server/ui files and the registry
        return
    script = build_script(d, m, [o for _, o in pending], dry)
    r = execute(script)
    if r.returncode:
        err = r.stderr
        if "RS_VALIDATION" in err:
            body = err.split("RS_VALIDATION", 1)[1].split("CONTEXT:")[0].strip()
            print(f"REJECTED {p['name']}:\n  " + body.replace("\n", "\n  "), file=sys.stderr)
        else:
            print(err, file=sys.stderr)
        sys.exit(2)
    print(("VALIDATED (dry run, rolled back): " if dry else "INSTALLED: ") + f"{p['name']} {p['version']} ({len(pending)} migration(s))")
    if not dry and not REMOTE:
        MIGRATIONS.mkdir(parents=True, exist_ok=True)
        stamp = int(time.strftime("%Y%m%d%H%M%S", time.gmtime()))
        for i, (src, out) in enumerate(pending):
            dest = MIGRATIONS / f"{stamp + i}_pack_{p['name'].replace('-', '_')}_{src.stem}.sql"
            shutil.copy(out, dest); print("  wrote", dest.relative_to(ROOT))
        app_install(d, m, Path(args.app) if args.app else None)

def cmd_remove(args):
    name = args.name
    have = installed_packs()
    if name not in have: die(f"{name} is not installed")
    for other in have:
        if other == name: continue
        d, m, _ = load_pack(other)
        if name in m["pack"].get("requires", []): die(f"installed pack '{other}' requires '{name}'")
    d, m, mig = load_pack(name)
    rb = sorted((d / "rollback").glob("*.sql"), reverse=True)
    body = "\n".join(f"-- {f.name}\n{f.read_text()}" for f in rb) + f"\ndelete from public.pack_migrations where pack = '{name}';\n"
    r = execute("begin;\n" + body + "\ncommit;")
    if r.returncode: die(r.stderr)
    if getattr(args, "app", None): app_uninstall(name, args.app)
    if REMOTE: print("REMOVED", name, f"(remote {REMOTE})"); return
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    dest = MIGRATIONS / f"{stamp}_pack_{name.replace('-', '_')}_remove.sql"
    dest.write_text(body); print("REMOVED", name, "->", dest.relative_to(ROOT))

def _app_dir(app):
    return (ROOT / app) if not Path(app).is_absolute() else Path(app)

def app_install(d, m, app):
    """Copy server/ (-> app/api/<pack>) and ui/ (mirrors the (app) route tree) into the app; regenerate the registry.
    Ownership of every copied file is recorded so two packs can never silently overwrite each other and `pack remove` cleans up."""
    if not app: return
    app = _app_dir(app); name = m["pack"]["name"]
    owners_f = app / "lib" / "packs" / "owners.json"
    owners = json.loads(owners_f.read_text()) if owners_f.exists() else {}
    for sub, dest in (("server", app / "app" / "api" / name), ("ui", app / "app" / "(app)")):
        src = d / sub
        if not src.is_dir(): continue
        for f in sorted(x for x in src.rglob("*") if x.is_file()):
            target = dest / f.relative_to(src); rel = str(target.relative_to(app))
            if owners.get(rel, name) != name: die(f"{rel} is already owned by pack '{owners[rel]}'")
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(f, target); owners[rel] = name
        print("  copied", sub, "->", dest.relative_to(ROOT))
    owners_f.parent.mkdir(parents=True, exist_ok=True); owners_f.write_text(json.dumps(owners, indent=1, sort_keys=True) + "\n")
    write_registry(app)

def app_uninstall(name, app):
    app = _app_dir(app); owners_f = app / "lib" / "packs" / "owners.json"
    if not owners_f.exists(): return
    owners = json.loads(owners_f.read_text())
    for rel in [r for r, o in owners.items() if o == name]:
        (app / rel).unlink(missing_ok=True); del owners[rel]
        for parent in (app / rel).parents:  # prune emptied directories inside the app tree
            if parent == app or any(parent.iterdir()): break
            parent.rmdir()
    owners_f.write_text(json.dumps(owners, indent=1, sort_keys=True) + "\n"); write_registry(app)

def write_registry(app):
    reg = {"nav": [dict(label="Billing plans", href="/admin/billing-plans", icon="CreditCard", group="admin", pack="core")], "limits": {},
           "health": [dict(id="bw_unmatched_events", pack="core")], "events": [], "operations": []}
    for name in sorted(installed_packs()):
        try: _, m, _ = load_pack(name)
        except SystemExit: continue
        reg["nav"] += [dict(e, pack=name) for e in m.get("nav", {}).get("entries", [])]
        reg["limits"].update({k: v.get("default") for k, v in m.get("limits", {}).items()})
        reg["health"] += [dict(id=c, pack=name) for c in m.get("health", {}).get("checks", [])]
        reg["events"] += m.get("events", {}).get("loops", [])
        reg["operations"] += [dict(o, pack=name) for o in m.get("credits", {}).get("operations", [])]
    out = app / "lib" / "packs" / "registry.generated.ts"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("// GENERATED by tools/rapscalyon.py. Do not edit.\nexport const packRegistry = " + json.dumps(reg, indent=2) + " as { nav: { label: string; href: string; icon: string; group: string; pack: string }[]; limits: Record<string, number>; health: { id: string; pack: string }[]; events: unknown[]; operations: unknown[] };\n")
    print("  wrote", out.relative_to(ROOT))

def cmd_core(_):
    """Apply the core foundation migration (once) and the idempotent core storage migration to the target database."""
    foundation_present = query("select to_regclass('public.pack_migrations') is not null").lower() in ("t", "true")
    core = sorted(MIGRATIONS.glob("*_core_foundation.sql"))[0]
    storage = sorted(MIGRATIONS.glob("*_core_storage.sql"))
    billing = sorted(MIGRATIONS.glob("*_core_billing.sql"))
    if foundation_present: print("core already present")
    else:
        r = execute("begin;\n" + core.read_text() + "\ncommit;")
        if r.returncode: die(r.stderr)
        print("CORE APPLIED", core.name)
    if storage and query("select to_regclass('storage.objects') is not null").lower() in ("t", "true"):
        r = execute("begin;\n" + storage[0].read_text() + "\ncommit;")
        if r.returncode: die(r.stderr)
        print("CORE STORAGE APPLIED", storage[0].name)
    if billing:  # idempotent, so databases that had the old billing-webhook pack are upgraded in place
        r = execute("begin;\n" + billing[0].read_text() + "\ncommit;")
        if r.returncode: die(r.stderr)
        print("CORE BILLING APPLIED", billing[0].name)

def cmd_catalog(args):
    """Build the pack catalog (docs/CATALOG.md and app/lib/packs/catalog.generated.ts) from every pack in packs/."""
    items = []
    for d in sorted(PACKS.iterdir()):
        if not (d / "pack.toml").exists(): continue
        m = tomllib.loads((d / "pack.toml").read_text())["pack"]
        mk = (d / "docs" / "MARKETING.md")
        if not mk.exists(): die(f"{d.name}: docs/MARKETING.md is required for the catalog")
        title, tagline, sections, cur = None, "", {}, None
        for line in mk.read_text().splitlines():
            if line.startswith("# "): title = line[2:].strip()
            elif line.startswith("> ") and not tagline: tagline = line[2:].strip()
            elif line.startswith("## "): cur = line[3:].strip(); sections[cur] = []
            elif cur and line.strip(): sections[cur].append(line[2:].strip() if line.startswith("- ") else line.strip())
        items.append(dict(name=m["name"], version=m["version"], tier=m.get("tier", "community"), license=m["license"],
                          description=m["description"], title=title, tagline=tagline, sections=sections))
    md = ["# Pack catalog", "", "Generated by `tools/rapscalyon.py catalog`.", ""]
    for i in items:
        md += [f"## {i['title']} (`{i['name']}` {i['version']}, {i['tier']})", "", f"> {i['tagline']}", ""]
        for sec, lines in i["sections"].items():
            md += [f"**{sec}**", ""] + [("- " + l if len(lines) > 1 and sec == "What you get" else l) for l in lines] + [""]
    (ROOT / "docs").mkdir(exist_ok=True); (ROOT / "docs" / "CATALOG.md").write_text("\n".join(md))
    out = ROOT / "app" / "lib" / "packs" / "catalog.generated.ts"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("// GENERATED by tools/rapscalyon.py catalog. Do not edit.\nexport type CatalogEntry = { name: string; version: string; tier: string; license: string; description: string; title: string; tagline: string; sections: Record<string, string[]> };\nexport const catalog: CatalogEntry[] = " + json.dumps(items, indent=1) + ";\n")
    kb = ROOT / "pickaxe" / "kb" / "platform"; kb.mkdir(parents=True, exist_ok=True)
    for f in kb.glob("*.md"): f.unlink()
    for i in items:  # Tier-1 knowledge base: one short document per pack, uploaded to the Pickaxe interviewer
        body = [f"# {i['title']} ({i['name']})", "", i["tagline"], "", f"Tier: {i['tier']}. Version {i['version']}. {i['description']}", ""]
        for sec, lines in i["sections"].items(): body += [f"## {sec}", ""] + [("- " + l if sec == "What you get" else l) for l in lines] + [""]
        (kb / f"{i['name']}.md").write_text("\n".join(body))
    # Commercial packs from RAPSCALYON_PACKS_PATH get Tier-1 documents too, in a gitignored folder: the public catalog and kb/platform stay public-only.
    plus = ROOT / "pickaxe" / "kb" / "platform-plus"; n_plus = 0
    for root in EXTRA_PACKS:
        for d in sorted(root.iterdir()) if root.is_dir() else []:
            mk = d / "docs" / "MARKETING.md"
            if not (d / "pack.toml").exists() or not mk.exists(): continue
            m = tomllib.loads((d / "pack.toml").read_text())["pack"]
            plus.mkdir(parents=True, exist_ok=True)
            (plus / f"{m['name']}.md").write_text(f"{mk.read_text().rstrip()}\n\nPack: {m['name']} {m['version']}, {m.get('tier', 'commercial')} tier (private rapscalyon-plus repo, licence required; installs with RAPSCALYON_PACKS_PATH). {m['description']}\n")
            n_plus += 1
    print(f"catalog: {len(items)} packs" + (f" (+{n_plus} commercial knowledge documents in pickaxe/kb/platform-plus)" if n_plus else ""))

def cmd_list(_):
    for k, v in sorted(installed_packs().items()): print(f"{k} {v}")

def cmd_test(args):
    files = [ROOT / "tests" / "_helpers.sql"]
    suites = sorted((ROOT / "tests").glob("[0-9]*.sql"))
    if args.pack: suites = []
    names = [args.pack] if args.pack else sorted(installed_packs())
    for n in names:
        suites += sorted((pack_dir(n) / "tests").glob("*.sql"))
    failed = 0
    for s in suites:
        if REMOTE:
            # helpers are created inside this request's implicit transaction and rolled back with it
            r = run_remote(strip_meta(files[0].read_text()) + "\n" + strip_meta(s.read_text()) + "\nrollback;")
        else:
            r = psql(["-f", str(files[0]), "-f", str(s)])
        ok = r.returncode == 0
        print(("PASS " if ok else "FAIL ") + (str(s.relative_to(ROOT)) if s.is_relative_to(ROOT) else str(s)))
        if not ok: failed += 1; print("   " + r.stderr.strip().replace("\n", "\n   "))
    print(f"{len(suites) - failed}/{len(suites)} suites passed"); sys.exit(1 if failed else 0)

def main():
    global REMOTE
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    ap.add_argument("--project", default=os.environ.get("RS_PROJECT"), help="hosted Supabase project ref (default: local DATABASE_URL)")
    pk = sub.add_parser("pack").add_subparsers(dest="sub", required=True)
    a = pk.add_parser("add"); a.add_argument("pack"); a.add_argument("--dry-run", action="store_true"); a.add_argument("--app")
    v = pk.add_parser("validate"); v.add_argument("pack"); v.add_argument("--app"); v.add_argument("--dry-run", action="store_true", default=True)
    rm = pk.add_parser("remove"); rm.add_argument("name"); rm.add_argument("--app")
    pk.add_parser("list")
    sub.add_parser("core"); sub.add_parser("catalog")
    t = sub.add_parser("test"); t.add_argument("--pack")
    args = ap.parse_args()
    REMOTE = args.project
    if REMOTE in PROTECTED_REFS: die(f"refusing to run against protected project {REMOTE}")
    if args.cmd == "test": cmd_test(args)
    elif args.cmd == "core": cmd_core(args)
    elif args.cmd == "catalog": cmd_catalog(args)
    elif args.sub == "add": cmd_add(args)
    elif args.sub == "validate": cmd_add(args, dry_override=True)
    elif args.sub == "remove": cmd_remove(args)
    elif args.sub == "list": cmd_list(args)

if __name__ == "__main__":
    main()
