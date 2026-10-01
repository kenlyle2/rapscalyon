#!/usr/bin/env python3
"""Lifecycle / ordering / negative scenarios against demo instances f, g, h. Prints PASS/FAIL per check."""
import json, sys, shutil, tempfile, re
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import demo_matrix as dm, rapscalyon as rs
INST = dm.INST
res = []
def check(name, ok, detail=""):
    res.append(ok); print(("PASS " if ok else "FAIL ") + name + (f"  -- {detail[:300]}" if detail and not ok else ""), flush=True)
def add(k, p): return dm.rs(k, "pack", "add", p)
def rm(k, p): return dm.rs(k, "pack", "remove", p)
def q(k, s):
    rs.REMOTE = INST[k]; return rs.query(s)
def installed(k): return sorted(l.split()[0] for l in dm.rs(k, "pack", "list")[1].splitlines() if l.strip())

SEED = """
begin;
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
 values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','seed@example.test','{}','{}',now(),now());
insert into public.subjects (id, owner_id, kind, name) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','business','Seed Co');
insert into public.rel_listings (subject_id, created_by, title) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','seed listing');
insert into public.sp_posts (subject_id, created_by, body) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','seed post');
commit;"""

def fingerprint(k):
    rs.REMOTE = INST[k]
    return q(k, rs.FP_SQL)

def scenario_f():
    print("== f: lifecycle with data")
    k = "f"
    for p in ["subject-business", "team", "real-estate-listings", "social-posts"]:
        rc, out = add(k, p); check(f"f add {p}", rc == 0, out)
    rs.REMOTE = INST[k]; r = rs.run_remote(SEED); check("f seed data (as admin role)", r.returncode == 0, r.stderr)
    check("f rows present", q(k, "select (select count(*) from public.rel_listings)||','||(select count(*) from public.sp_posts)") == "1,1")
    rc, out = rm(k, "social-posts"); check("f remove social-posts", rc == 0, out)
    check("f social tables gone, listing data intact", q(k, "select (to_regclass('public.sp_posts') is null)::text||','||(select count(*) from public.rel_listings)") == "true,1")
    check("f operation_pricing rows of removed pack gone", q(k, "select count(*) from public.operation_pricing where pack='social-posts'") == "0")
    check("f core data intact (user, subject)", q(k, "select (select count(*) from public.profiles)||','||(select count(*) from public.subjects)") == "1,1")
    rc, out = add(k, "social-posts"); check("f re-add social-posts", rc == 0, out)
    r = dm.rs(k, "test"); check("f tests after remove+re-add", r[0] == 0, r[1])
    for p in ["real-estate-listings", "social-posts", "team"]:
        rc, out = rm(k, p); check(f"f remove {p}", rc == 0, out)
    rc, out = rm(k, "subject-business"); check("f remove subject-business (packs are independent of it)", rc == 0, out)
    check("f only core + seed remain", q(k, "select count(*) from information_schema.tables where table_schema='public' and table_name ~ '^(rel|sp|team|biz)_'") == "0")
    rc, out = add(k, "subject-individual"); check("f swap to subject-individual after removing business", rc == 0, out)

def scenario_g():
    print("== g: ordering / idempotency / lego independence")
    k = "g"
    rc, out = add(k, "real-estate-listings"); check("g real-estate works with NO subject pack (packs key on core subjects)", rc == 0, out)
    rc, out = add(k, "jobs-tracker"); check("g jobs-tracker works with NO subject pack (core subjects only)", rc == 0, out)
    rc, out = add(k, "jobs-tracker"); check("g re-adding is a no-op", rc == 0 and "already installed" in out, out)
    rc, out = add(k, "social-posts"); check("g social-posts alongside", rc == 0, out)
    rc, out = add(k, "subject-individual"); check("g subject pack added AFTER feature packs", rc == 0, out)
    rc, out = add(k, "team"); check("g team added last", rc == 0, out)
    r = dm.rs(k, "test"); check("g tests, shuffled order", r[0] == 0, r[1])

def scenario_h():
    print("== h: conflicts, upgrades, bad packs")
    k = "h"
    for p in ["subject-individual", "subject-business"]:
        rc, out = add(k, p); check(f"h add {p} (both subject flavours)", rc == 0, out)
    rc, out = add(k, "jobs-tracker"); check("h jobs-tracker over both", rc == 0, out)
    r = dm.rs(k, "test"); check("h tests with both subject packs", r[0] == 0, r[1])
    # upgrade: v0.2.0 of jobs-tracker with a 002 migration
    tmp = Path(tempfile.mkdtemp(prefix="rs-up-")) / "jobs-tracker"
    shutil.copytree(ROOT / "packs" / "jobs-tracker", tmp)
    (tmp / "migrations" / "002_add_source.sql").write_text("alter table public.jb_applications add column referrer text;\n")
    (tmp / "rollback" / "002_add_source.sql").write_text("alter table public.jb_applications drop column if exists referrer;\n")
    t = (tmp / "pack.toml").read_text().replace('version = "0.1.0"', 'version = "0.2.0"'); (tmp / "pack.toml").write_text(t)
    rc, out = dm.rs(k, "pack", "add", str(tmp)); check("h upgrade applies only the new migration", rc == 0 and "1 migration" in out, out)
    check("h upgrade column exists, registry has 2 files", q(k, "select (select count(*) from information_schema.columns where table_name='jb_applications' and column_name='referrer')||','||(select count(*) from public.pack_migrations where pack='jobs-tracker')") == "1,2")
    # bad packs leave no residue
    def bad(name, sql):
        d = Path(tempfile.mkdtemp(prefix="rs-bad-")) / name
        for s in ("migrations", "rollback", "docs"): (d / s).mkdir(parents=True)
        (d / "pack.toml").write_text(f'[pack]\nname = "{name}"\nprefix = "bad"\nversion = "0.1.0"\nlicense = "GPL-3.0-or-later"\nrequires_core = ">=0.1"\nrequires = []\nconflicts = []\n[db]\ntables = ["bad_t"]\nfunctions = []\napi_functions = []\n')
        (d / "docs" / "README.md").write_text("x"); (d / "docs" / "SECURITY.md").write_text("x")
        (d / "rollback" / "001.sql").write_text("drop table if exists public.bad_t;")
        (d / "migrations" / "001.sql").write_text(sql); return d
    base = "create table public.bad_t (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, v text); create index on public.bad_t(user_id);"
    cases = {
        "bad-usingtrue": base + " grant select on public.bad_t to authenticated; create policy bad_p on public.bad_t for select to authenticated using (true);",
        "bad-tblupdate": base + " grant select, update on public.bad_t to authenticated; create policy bad_p on public.bad_t for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));",
        "bad-core": base + " alter table public.profiles add column evil text;",
        "bad-definer": base + " create function public.bad_fn(p uuid) returns void language sql security definer as 'select 1'; grant execute on function public.bad_fn(uuid) to authenticated;",
    }
    for n, s in cases.items():
        rc, out = dm.rs(k, "pack", "add", str(bad(n, s)))
        check(f"h {n} rejected", rc != 0 and ("REJECTED" in out), out)
    check("h no residue from rejected packs", q(k, "select (to_regclass('public.bad_t') is null)::text||','||(select count(*) from information_schema.columns where table_name='profiles' and column_name='evil')") == "true,0")

def fingerprints():
    print("== core fingerprints (must be identical everywhere)")
    fps = {k: fingerprint(k) for k in INST}
    print(json.dumps(fps, indent=1))
    check("core fingerprint identical across all 8 instances", len(set(fps.values())) == 1, str(fps))

if __name__ == "__main__":
    which = sys.argv[1:] or ["f", "g", "h", "fp"]
    for w in which: {"f": scenario_f, "g": scenario_g, "h": scenario_h, "fp": fingerprints}[w]()
    print(f"\n{sum(res)}/{len(res)} checks passed")
