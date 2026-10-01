#!/usr/bin/env python3
"""Run the pack-combination matrix against the disposable hosted demo projects (tools/demo-instances.json)."""
import json, subprocess, sys, hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
INST = json.load(open(ROOT / "tools" / "demo-instances.json"))
TOOL = [sys.executable, str(ROOT / "tools" / "rapscalyon.py")]

def rs(k, *a, retries=2):
    for i in range(retries + 1):
        r = subprocess.run([*TOOL, "--project", INST[k], *a], capture_output=True, text=True, cwd=ROOT)
        out = (r.stdout + r.stderr).strip()
        if r.returncode and ("PostHog" in out or "Timeout" in out or "unexpected EOF" in out) and i < retries: continue
        return r.returncode, out

def sql(k, q):
    import importlib; m = importlib.import_module("rapscalyon"); m.REMOTE = INST[k]
    return m.query(q)

PLANS = {
  "a": ["subject-individual", "jobs-tracker", "social-posts"],
  "b": ["subject-business", "team", "real-estate-listings", "social-posts"],
  "c": [],
  "d": ["subject-individual", "team", "jobs-tracker"],
  "e": ["subject-business", "team", "real-estate-listings", "jobs-tracker", "social-posts"],
}
log = []
def say(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); log.append(s)

def install(k, packs):
    for p in packs:
        rc, out = rs(k, "pack", "add", p)
        say(f"  [{k}] add {p}: {'ok' if rc == 0 else 'FAIL'} {'' if rc == 0 else out[:300]}")

def run_tests(k):
    rc, out = rs(k, "test")
    say(f"  [{k}] tests rc={rc}: {out.splitlines()[-1] if out else ''}")
    if rc: say(out[:1500])

def main(which):
    sys.path.insert(0, str(ROOT / "tools"))
    for k in which:
        say(f"== instance {k} ({INST[k]})")
        if k in PLANS:
            have = rs(k, "pack", "list")[1].split("\n")
            todo = [p for p in PLANS[k] if not any(l.startswith(p + " ") for l in have)]
            install(k, todo); run_tests(k)
        say(f"  [{k}] installed: {rs(k, 'pack', 'list')[1].replace(chr(10), ', ') or '(core only)'}")
    Path(ROOT / "tools" / "demo-matrix.log").write_text("\n".join(log) + "\n")

if __name__ == "__main__":
    main(sys.argv[1:] or ["a", "b", "c", "d", "e"])
