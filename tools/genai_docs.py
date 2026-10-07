#!/usr/bin/env python3
"""Keeps the GenAI-Logic knowledge document in Pickaxe current.

  python3 tools/genai_docs.py check      # are the pages or the releases different from the last build? (exit 1 if so)
  python3 tools/genai_docs.py build      # fetch the 25 pages, write the merged document, update the state file
  python3 tools/genai_docs.py publish    # replace the workspace document with the built one (changes Pickaxe; run it on purpose)

Dependency-free. The pages come from https://apilogicserver.github.io/Docs/<Page>/ (third-party documentation: the
merged text is written to a build directory, never committed). State lives in pickaxe/kb/genai-logic.state.json.
After a publish, re-run the retrieval questions in packs/invoice-refunds/rules/poc/run_scenarios.py.
"""
import hashlib, json, os, re, sys, time, urllib.request
from datetime import date
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, 'pickaxe', 'kb', 'genai-logic.state.json')
BUILD = os.environ.get('GENAI_DOCS_BUILD', os.path.join(os.path.expanduser('~'), '.cache', 'rapscalyon', 'genai-docs'))
BASE = 'https://apilogicserver.github.io/Docs/'
PAGES = ['API', 'API-Customize', 'Architecture-Declarative-Automation', 'Architecture-Security-Auth', 'Architecture-What-Is',
         'Architecture-What-Is-GenAI', 'Behave', 'Behave-Creation', 'Behave-Logic-Report', 'Data-Model-Design', 'Integration-EAI',
         'Integration-MCP', 'Logic', 'Logic-Operation', 'Logic-Type-Constraint', 'Logic-Type-Copy', 'Logic-Type-Events',
         'Logic-Type-Formula', 'Logic-Type-Sum', 'Logic-Use', 'Logic-Why', 'Logic-Why-Declarative-GenAI', 'Sample-Basic-Demo',
         'Security-Authorization', 'Security-Overview']
PYPI = ['logicbank', 'ApiLogicServer']
DOC_NAME = 'genai-logic-docs'
WORKSPACE_AGENTS = ['NWCR3HQ6JB0D', 'ZWRT9WUT8NLR']  # Stack Interviewer, Pack Builder
SKIP = {'script', 'style', 'nav', 'svg', 'button', 'form', 'footer'}


class Article(HTMLParser):
    """Turns the <article> element of a mkdocs-material page into plain markdown."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.inside = 0; self.skip = []; self.out = []; self.pre = False; self.cell = False; self.row = []; self.href = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'article': self.inside = 1; return
        if not self.inside: return
        if self.skip:  # inside a skipped element: track same-named nesting so its end tag is matched
            if tag == self.skip[-1]: self.skip.append(tag)
            return
        if tag in SKIP or 'headerlink' in (a.get('class') or ''): self.skip.append(tag); return
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'): self.out.append('\n\n' + '#' * int(tag[1]) + ' ')
        elif tag in ('p', 'br') and self.cell and self.row: self.row[-1] += ' '
        elif tag == 'p': self.out.append('\n\n')
        elif tag == 'li': self.out.append('\n- ')
        elif tag == 'pre': self.pre = True; self.out.append('\n\n```\n')
        elif tag == 'br': self.out.append('\n')
        elif tag == 'tr': self.row = []
        elif tag in ('td', 'th'): self.cell = True; self.row.append('')
        elif tag == 'code' and not self.pre: self.out.append('`')

    def handle_endtag(self, tag):
        if tag == 'article': self.inside = 0; return
        if not self.inside: return
        if self.skip:
            if tag == self.skip[-1]: self.skip.pop()
            return
        if tag == 'pre': self.pre = False; self.out.append('\n```')
        elif tag == 'code' and not self.pre: self.out.append('`')
        elif tag in ('td', 'th'): self.cell = False
        elif tag == 'tr' and self.row: self.out.append('\n| ' + ' | '.join(c.strip() for c in self.row) + ' |')

    def handle_data(self, data):
        if not self.inside or self.skip: return
        if self.cell and self.row: self.row[-1] += data
        elif self.pre: self.out.append(data)
        else: self.out.append(re.sub(r'\s+', ' ', data))

    def text(self):
        t = ''.join(self.out)
        return re.sub(r'\n{3,}', '\n\n', t).strip() + '\n'


def get(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'rapscalyon-docs-check'}), timeout=30) as r:
                return r.read().decode('utf-8', 'replace')
        except Exception:
            if attempt == 2: raise
            time.sleep(2)


def page_text(name):
    p = Article(); p.feed(get(f'{BASE}{name}/')); t = p.text()
    if len(t) < 100: raise SystemExit(f'{name}: page came back nearly empty ({len(t)} chars); the site layout may have changed')
    return t


def versions():
    return {p: json.load(urllib.request.urlopen(f'https://pypi.org/pypi/{p}/json', timeout=30))['info']['version'] for p in PYPI}


def sha(t): return hashlib.sha256(t.encode()).hexdigest()


def load_state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def cmd_check():
    st = load_state(); old_v = st.get('versions', {}); old_h = st.get('pages', {}); changed = []
    new_v = versions()
    for p in PYPI:
        if old_v.get(p) != new_v[p]: changed.append(f'release {p}: {old_v.get(p)} -> {new_v[p]}')
    for n in PAGES:
        h = sha(page_text(n))
        if old_h.get(n) != h: changed.append(f'page {n}: ' + ('new' if n not in old_h else 'changed'))
    print(f'last build: {st.get("built", "never")}')
    print('\n'.join(changed) if changed else 'GenAI-Logic docs and releases unchanged since the last build.')
    sys.exit(1 if changed else 0)


def cmd_build():
    os.makedirs(BUILD, exist_ok=True); pages = {}; parts = []
    for n in PAGES:
        t = page_text(n); pages[n] = sha(t); parts.append(f'\n\n==================== GenAI-Logic: {n} ====================\n\n{t}')
    merged = f"GenAI-Logic documentation, {len(PAGES)} pages merged. Each page starts with a banner line 'GenAI-Logic: <page>'.\n" + ''.join(parts)
    path = os.path.join(BUILD, DOC_NAME + '.txt'); open(path, 'w').write(merged)
    state = {'built': date.today().isoformat(), 'versions': versions(), 'pages': pages, 'merged_sha256': sha(merged), 'chars': len(merged)}
    os.makedirs(os.path.dirname(STATE), exist_ok=True); json.dump(state, open(STATE, 'w'), indent=2); open(STATE, 'a').write('\n')
    print(f'wrote {path} ({len(merged):,} chars) and {os.path.relpath(STATE, ROOT)}')


def cmd_publish():
    sys.path.insert(0, os.environ.get('PICKAXE_CLIENT', os.path.expanduser('~/.claude/skills/pickaxe/scripts')))
    from pickaxe_client import call
    path = os.path.join(BUILD, DOC_NAME + '.txt')
    if not os.path.exists(path): raise SystemExit('run build first')
    text = open(path).read()
    if sha(text) != load_state().get('merged_sha256'): raise SystemExit('the built file does not match the state file; run build again')
    docs = call('document_list', {'skip': 0, 'take': 100}); docs = docs if isinstance(docs, list) else docs.get('documents', docs)
    old = [d['documentId'] for d in docs if d['displayName'] == DOC_NAME]
    # The workspace is capped at 50 documents, so the old copy goes first. Out of service for a few seconds.
    for did in old:
        for agent in WORKSPACE_AGENTS:
            try: call('document_disconnect', {'documentId': did, 'pickaxeId': agent})
            except Exception: pass
        call('document_delete', {'document_id': did})
    new = call('document_create', {'name': DOC_NAME, 'rawContent': text})
    for agent in WORKSPACE_AGENTS: call('document_connect', {'documentId': new['documentId'], 'pickaxeId': agent})
    print(f"replaced: new document {new['documentId']}, {new.get('chunkCount')} chunks, embedding {new.get('embeddingFillStatus')}")


if __name__ == '__main__':
    cmds = {'check': cmd_check, 'build': cmd_build, 'publish': cmd_publish}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds: raise SystemExit(__doc__)
    cmds[sys.argv[1]]()
