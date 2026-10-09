#!/usr/bin/env python3
"""Keeps the Pickaxe knowledge documents that come from this repo in step with it.

  python3 tools/kb_sync.py check               # which documents differ from what was last published? (exit 1 if any; reads the repo only)
  python3 tools/kb_sync.py adopt               # read-only against Pickaxe: record each document's id, agents and live text hash in the manifest
  python3 tools/kb_sync.py publish [name ...]  # replace stale (or named) documents in Pickaxe (changes the live workspace; run it on purpose)

The manifest is pickaxe/kb/docs.json. Each entry: name, build (a pack group or one file), agents, documentId, publishedSha256, catalogVersion.
Replace order is create, connect, disconnect, delete, then a read-back of the attachment and the text (the workspace is capped at 50 documents).
Pack groups are built from pickaxe/kb/platform/*.md (run `rapscalyon.py catalog` first). Commercial packs are not here: their documents are
built from the private repo and published by hand. Dependency-free; Pickaxe calls use the pickaxe skill client.
"""
import hashlib, json, os, sys, urllib.request
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, 'pickaxe', 'kb', 'docs.json')
KB = os.path.join(ROOT, 'pickaxe', 'kb')
CDN = 'https://cdn.mail.studio/documentinterrogation/text/{}.txt'


def sha(t): return hashlib.sha256(t.encode()).hexdigest()
def load(): return json.load(open(MANIFEST))
def save(m): json.dump(m, open(MANIFEST, 'w'), indent=1); open(MANIFEST, 'a').write('\n')


def official_packs():
    reg = json.load(open(os.path.join(ROOT, 'registry', 'packs.json')))
    return sorted(n for n, p in reg['packs'].items() if p['tier'] == 'official'), reg['catalogVersion']


def build(entry):
    """Text of one document, exactly as it is uploaded."""
    b = entry['build']
    if b['kind'] == 'file':
        # private documents live in a separate private checkout; point RAPSCALYON_APP_PATH at it
        for base in (KB, os.path.join(os.environ.get('RAPSCALYON_APP_PATH', '/nonexistent'), 'pickaxe', 'kb')):
            if os.path.exists(os.path.join(base, b['path'])): return open(os.path.join(base, b['path'])).read()
        return None
    names, _ = official_packs()
    if b.get('members') == 'rest':  # every official pack not named in another group
        taken = {n for e in load()['docs'] if e['build'].get('kind') == 'packs' and isinstance(e['build'].get('members'), list) for n in e['build']['members']}
        members = [n for n in names if n not in taken]
    else:
        members = b['members']
    missing = [n for n in members if not os.path.exists(os.path.join(KB, 'platform', n + '.md'))]
    if missing: raise SystemExit(f"{entry['name']}: no kb/platform document for {missing}; run `python3 tools/rapscalyon.py catalog`")
    return '\n\n'.join(open(os.path.join(KB, 'platform', n + '.md')).read().strip() for n in members) + '\n\n'


def cmd_check():
    m = load(); _, cv = official_packs(); stale = []
    for e in m['docs']:
        text = build(e)
        if text is None: print(f"skip  {e['name']:34} private source not available (set RAPSCALYON_APP_PATH)"); continue
        h = sha(text)
        state = 'ok' if h == e.get('publishedSha256') else 'STALE'
        if state != 'ok': stale.append(e['name'])
        print(f"{state:5} {e['name']:34} {e.get('documentId', '-')}")
    print(f"catalog {cv}; {len(stale)} stale of {len(m['docs'])}")
    sys.exit(1 if stale else 0)


def client():
    sys.path.insert(0, os.environ.get('PICKAXE_CLIENT', os.path.expanduser('~/.claude/skills/pickaxe/scripts')))
    from pickaxe_client import call
    return call


def cmd_adopt():
    call = client(); m = load(); live = {}
    for agent in m['agents']:
        for d in call('pickaxe_documents', {'pickaxeId': agent})['documents']:
            live.setdefault(d['displayName'], {'id': d['documentId'], 'agents': []})['agents'].append(agent)
    for e in m['docs']:
        d = live.get(e['name'])
        if not d: print(f"not attached anywhere: {e['name']}"); continue
        e['documentId'] = d['id']; e['agents'] = sorted(d['agents'])
        e['publishedSha256'] = sha(urllib.request.urlopen(CDN.format(d['id'])).read().decode())
        print(f"adopted {e['name']} {d['id']} on {e['agents']}")
    save(m)


def cmd_publish(only):
    call = client(); m = load(); _, cv = official_packs()
    for e in m['docs']:
        text = build(e)
        if text is None: print(f"skip {e['name']}: private source not available (set RAPSCALYON_APP_PATH)"); continue
        if (only and e['name'] not in only) or (not only and sha(text) == e.get('publishedSha256')): continue
        old = e.get('documentId')
        new = call('document_create', {'name': e['name'], 'title': e['name'], 'documentType': 'text', 'rawContent': text})['documentId']
        for a in e['agents']: call('document_connect', {'pickaxeId': a, 'documentId': new})
        if old:
            for a in e['agents']: call('document_disconnect', {'pickaxeId': a, 'documentId': old})
            call('document_delete', {'document_id': old})
        for a in e['agents']:  # read back: attached, old gone, text equal
            ids = [d['documentId'] for d in call('pickaxe_documents', {'pickaxeId': a})['documents']]
            assert new in ids and old not in ids, f"{e['name']}: attachment check failed on {a}"
        assert sha(urllib.request.urlopen(CDN.format(new)).read().decode()) == sha(text), f"{e['name']}: stored text differs"
        e.update(documentId=new, publishedSha256=sha(text), catalogVersion=cv, publishedOn=date.today().isoformat())
        save(m); print(f"replaced {e['name']}: {old} -> {new} (read back equal)")


if __name__ == '__main__':
    c = sys.argv[1:2]
    if c == ['check']: cmd_check()
    elif c == ['adopt']: cmd_adopt()
    elif c == ['publish']: cmd_publish(sys.argv[2:])
    else: raise SystemExit(__doc__)
