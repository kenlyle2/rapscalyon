#!/usr/bin/env python3
"""Install every official pack on a FRESH local database, run the tests, remove them in reverse order, and require an empty result.

  python3 tools/ci_packs.py            # uses DATABASE_URL (default: local Supabase on :54322). Run on a throwaway database only.
  python3 tools/ci_packs.py --plan     # print the order and stop (no database needed)

Order comes from [pack].requires in registry/packs.json. A pack that cannot be removed cleanly fails the run, so rollback is exercised too.
Packs installed on a developer's own scratch database are not touched by --plan, but a real run installs and removes: do not point it at one.
"""
import json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = [sys.executable, str(ROOT / "tools" / "rapscalyon.py")]


def order(packs):
    done, out = set(), []
    def visit(n, trail=()):
        if n in done: return
        if n in trail: raise SystemExit(f"requires cycle: {' -> '.join(trail + (n,))}")
        if n not in packs: raise SystemExit(f"{trail[-1] if trail else '?'} requires {n}, which is not an official pack in registry/packs.json")
        for r in packs[n]["requires"]: visit(r, trail + (n,))
        done.add(n); out.append(n)
    for n in sorted(packs): visit(n)
    return out


def run(*args):
    print("+", " ".join(args), flush=True)
    r = subprocess.run([*CLI, *args], cwd=ROOT)
    if r.returncode: raise SystemExit(f"failed: {' '.join(args)}")


def main():
    packs = {n: p for n, p in json.loads((ROOT / "registry" / "packs.json").read_text())["packs"].items() if p["tier"] == "official"}
    seq = order(packs)
    print("order:", ", ".join(seq))
    if "--plan" in sys.argv: return
    run("core")
    run("test")                       # core suites
    for n in seq: run("pack", "add", n)
    run("test")                       # every installed pack's suites together
    for n in reversed(seq): run("pack", "remove", n)
    left = subprocess.run([*CLI, "pack", "list"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if left: raise SystemExit("packs left after removal:\n" + left)
    stray = sorted(f.name for f in (ROOT / "supabase" / "migrations").glob("*_pack_*.sql"))
    if stray: raise SystemExit("pack removal left generated replay files (supabase db reset would replay them):\n  " + "\n  ".join(stray))
    # the preflight must refuse a database holding a table nobody declares
    url = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
    sql = lambda q: subprocess.run(["psql", url, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c", q], check=True, capture_output=True)
    sql("create table public.zz_stray (id int)")
    try:
        r = subprocess.run([*CLI, "test"], cwd=ROOT, capture_output=True, text=True)
        if r.returncode == 0 or "zz_stray" not in r.stderr: raise SystemExit("preflight did not refuse a database holding an undeclared table")
    finally:
        sql("drop table public.zz_stray")
    print(f"ok: {len(seq)} packs installed, tested and removed cleanly; preflight refuses undeclared tables")


if __name__ == "__main__":
    main()
