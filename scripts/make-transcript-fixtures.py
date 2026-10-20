"""Cut a real local Transcript of each vendor to a short fixture, and scrub every free text value.

Usage: python3 -I scripts/make-transcript-fixtures.py Packages/MuxifyCore/Tests/MuxifyCoreTests/Fixtures <opencode session id>

Each fixture keeps the records of the real format and the vendor version in its file name. Read the result before
you commit it: the scrub replaces string values, but not the keys in KEEP.
"""
import glob, json, os, subprocess, sys

OUT = sys.argv[1]
KEEP = {'type', 'role', 'name', 'tool', 'timestamp', 'id', 'call_id', 'tool_use_id', 'toolCallId', 'toolName', 'status',
        'uuid', 'parentUuid', 'parentId', 'sessionId', 'session_id', 'version', 'cli_version', 'phase', 'kind', 'created'}
counter = [0]

def scrub(value, key=None):
    if isinstance(value, dict):
        return {k: scrub(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v, key) for v in value]
    if isinstance(value, str) and key == 'arguments':
        try:
            return json.dumps(scrub(json.loads(value)), separators=(',', ':'))
        except ValueError:
            pass
    if isinstance(value, str) and key not in KEEP:
        counter[0] += 1
        return 'scrubbed %d' % counter[0]
    return value

def jsonl(path, want, limit, keep_record):
    """Records from the start of `path` until each wanted shape was seen, at most `limit` records."""
    seen, out = set(), []
    for line in open(path):
        record = json.loads(line)
        shape = keep_record(record)
        if shape is None:
            continue
        if shape in seen and len(out) >= 4:
            continue
        seen.add(shape)
        out.append(record)
        if want <= seen or len(out) >= limit:
            break
    missing = want - seen
    if missing:
        raise SystemExit('%s lacks %s' % (path, missing))
    return out

def write(name, records):
    counter[0] = 0
    with open(os.path.join(OUT, name), 'w') as f:
        for r in records:
            f.write(json.dumps(scrub(r), separators=(',', ':')) + '\n')

def parts(content):
    return tuple(sorted({p.get('type') for p in content})) if isinstance(content, list) else type(content).__name__

def claude_shape(r):
    m = r.get('message') or {}
    t = r.get('type')
    if t in ('user', 'assistant'):
        return (t, parts(m.get('content')), bool(r.get('isMeta')))
    return ('other', t)

def claude():
    want = {('user', 'str', False), ('assistant', ('text',), False), ('assistant', ('thinking',), False),
            ('assistant', ('tool_use',), False), ('user', ('tool_result',), False), ('user', ('text',), True),
            ('other', 'attachment')}
    for path in sorted(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')), key=os.path.getmtime, reverse=True):
        try:
            records = jsonl(path, want, 40, claude_shape)
        except SystemExit:
            continue
        version = next(r['version'] for r in records if r.get('version'))
        write('claude-%s.jsonl' % version, records)
        return

def codex():
    def shape(r):
        p = r.get('payload') or {}
        item = p.get('item') if isinstance(p.get('item'), dict) else {}
        return (r.get('type'), p.get('type'), p.get('role'), item.get('type'))
    want = {('event_msg', 'item_completed', None, 'UserMessage'), ('event_msg', 'item_completed', None, 'AgentMessage'),
            ('response_item', 'message', 'assistant', None), ('response_item', 'custom_tool_call', None, None),
            ('response_item', 'custom_tool_call_output', None, None), ('response_item', 'function_call', None, None),
            ('response_item', 'function_call_output', None, None), ('response_item', 'reasoning', None, None)}
    for path in sorted(glob.glob(os.path.expanduser('~/.codex/sessions/**/*.jsonl'), recursive=True), key=os.path.getmtime, reverse=True):
        try:
            records = jsonl(path, want, 60, shape)
        except SystemExit:
            continue
        version = json.loads(open(path).readline())['payload']['cli_version']
        write('codex-%s.jsonl' % version, records)
        return

def pi():
    def shape(r):
        m = r.get('message') or {}
        return (r.get('type'), m.get('role'), parts(m.get('content')) if m else None)
    want = {('message', 'user', ('text',)), ('message', 'assistant', ('thinking', 'toolCall')),
            ('message', 'toolResult', ('text',)), ('message', 'assistant', ('text', 'thinking'))}
    for path in glob.glob(os.path.expanduser('~/.pi/agent/sessions/**/*.jsonl'), recursive=True):
        try:
            records = jsonl(path, want, 20, shape)
        except SystemExit:
            continue
        version = next(r['version'] for r in records if r.get('type') == 'session')
        write('pi-v%s.jsonl' % version, records)
        return

def opencode(session):
    version = subprocess.run(['opencode', '--version'], capture_output=True, text=True).stdout.strip()
    data = json.loads(subprocess.run(['opencode', 'export', session], capture_output=True, text=True).stdout)
    counter[0] = 0
    with open(os.path.join(OUT, 'opencode-%s-export.json' % version), 'w') as f:
        json.dump(scrub(data), f, indent=1)
        f.write('\n')

claude(); codex(); pi(); opencode(sys.argv[2])
print(sorted(os.listdir(OUT)))
