#!/usr/bin/env python3
"""Bring every demo instance to the current core and add its share of the newer packs, then run the suites."""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
INST = json.loads((ROOT / "tools" / "demo-instances.json").read_text())
EXTRA = {"a": ["loops-email", "posthog-analytics"], "b": ["turnstile", "billing-webhook"], "d": ["loops-email", "billing-webhook"],
         "f": ["turnstile", "posthog-analytics"], "g": ["loops-email", "turnstile", "posthog-analytics", "billing-webhook"], "h": ["billing-webhook"]}
def rs(ref, *a):
    for _ in range(2):
        r = subprocess.run(["python3", str(ROOT / "tools" / "rapscalyon.py"), "--project", ref, *a], capture_output=True, text=True)
        if r.returncode == 0 or "ERROR" in r.stdout + r.stderr: break
    return r.returncode, (r.stdout + r.stderr).strip()
bad = 0
for k, ref in INST.items():
    rc, out = rs(ref, "core"); print(f"[{k}] core: {out.splitlines()[-1] if out else rc}")
    have = rs(ref, "pack", "list")[1]
    for p in EXTRA.get(k, []):
        if p in have: continue
        rc, out = rs(ref, "pack", "add", str(ROOT / "packs" / p)); print(f"[{k}] add {p}: rc={rc} {out.splitlines()[-1] if out else ''}"); bad += rc != 0
    rc, out = rs(ref, "test"); print(f"[{k}] tests rc={rc}: {out.splitlines()[-1]}"); bad += rc != 0
    if rc: print(out)
print("FAILURES:", bad)
