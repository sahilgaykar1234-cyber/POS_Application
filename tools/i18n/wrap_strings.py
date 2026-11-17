#!/usr/bin/env python3
"""Wraps user-visible string literals in lib/ with tr('...').

    python3 tools/i18n/wrap_strings.py wrap      # rewrite sources
    python3 tools/i18n/wrap_strings.py fixconst  # analyzer loop: drop const / revert
    python3 tools/i18n/wrap_strings.py keys      # list every tr() key (JSON)

Interpolated strings become templates: 'Hi $name' -> tr('Hi {0}', [name]).
A literal is wrapped only when it looks like text for people (a space or a
capital letter) and is not in a data position (map key, comparison, Key(),
Firestore path, switch pattern ...).
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.path.join(ROOT, 'lib')

EXCLUDE = [
    'lib/features/admin/',
    'lib/features/receipt/receipt_html.dart', 'lib/features/receipt/receipt_view.dart', 'lib/features/receipt/receipt_data.dart',
    'lib/features/reports/day_end_report.dart', 'lib/features/reports/reports_csv.dart',
    'lib/features/orders/whatsapp_bill.dart', 'lib/features/orders/whatsapp_launch.dart',
    'lib/features/orders/bill_numbers.dart', 'lib/features/orders/bill.dart',
    'lib/features/pos/pos_cart.dart', 'lib/features/menu/menu_models.dart', 'lib/features/menu/menu_repository.dart',
    'lib/features/settings/business_settings.dart', 'lib/features/customers/customer_privacy.dart',
    'lib/core/theme/', 'lib/core/utils/formatters.dart', 'lib/core/utils/business_day.dart',
    'lib/core/data/', 'lib/core/config/', 'lib/core/services/', 'lib/core/web/', 'lib/core/i18n/',
    'lib/escpos', 'lib/reports_',
]

# Values that are stored data; wrapped only in plain display positions.
DATA_VALUES = {'Dine-In', 'Takeaway', 'Walk-in', 'Walk-in Guest', 'Counter Customer', 'Inter'}
DISPLAY_CTX = re.compile(r'(Text\(|label:|title:|tooltip:|subtitle:|caption:|message:)\s*$')

BAD_BEFORE = re.compile(
    r'(Key\(|ValueKey(<\w+>)?\(|collection\(|\.doc\(|where\(|orderBy\(|==|!=|\bcase|RegExp\(|\.log\(|startsWith\(|endsWith\(|'
    r'contains\(|split\(|replaceAll\(|replaceFirst\(|get(String|Int|Bool)\(|set(String|Int|Bool)\(|DateFormat\(|Uri\.parse\(|Uri\(|'
    r'debugPrint\(|print\(|value:|fontFamily:|family:|heroTag:|name:|id:|field:|contentType:|mimeType:|fileName:|filename:|'
    r'type:|cafeId:|\|\||\bimport|\bexport|\bpart|semanticsIdentifier:|restorationId:|_s\(|\bin)\s*$')
INDEX_BEFORE = re.compile(r'[\w\)\]\?!]\s*\[\s*$')


def excluded(rel):
    return any(rel.startswith(e) for e in EXCLUDE)


def skip_ws_comments(s, i):
    n = len(s)
    while i < n:
        if s[i].isspace():
            i += 1
        elif s.startswith('//', i):
            j = s.find('\n', i)
            i = n if j < 0 else j + 1
        elif s.startswith('/*', i):
            j = s.find('*/', i)
            i = n if j < 0 else j + 2
        else:
            break
    return i


def scan_expr_braces(s, i):
    """s[i] is just after '{' of '${'. Return index of matching '}'."""
    depth = 1
    n = len(s)
    while i < n:
        c = s[i]
        if c in '\'"':
            i, _ = scan_string(s, i)
            continue
        if c == 'r' and i + 1 < n and s[i + 1] in '\'"' and not (i > 0 and (s[i - 1].isalnum() or s[i - 1] == '_')):
            i, _ = scan_string(s, i)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def scan_string(s, i):
    """Scan one literal starting at s[i] (quote or r). Returns (end, info)."""
    raw = False
    if s[i] == 'r':
        raw = True
        i += 1
    q = s[i]
    triple = s.startswith(q * 3, i)
    start = i
    i += 3 if triple else 1
    parts = []  # ('t', rawtext) | ('e', exprsrc)
    buf = ''
    n = len(s)
    while i < n:
        if triple and s.startswith(q * 3, i):
            i += 3
            break
        c = s[i]
        if not triple and c == q:
            i += 1
            break
        if c == '\\' and not raw:
            buf += s[i:i + 2]
            i += 2
            continue
        if c == '$' and not raw:
            if i + 1 < n and s[i + 1] == '{':
                end = scan_expr_braces(s, i + 2)
                if buf:
                    parts.append(('t', buf))
                    buf = ''
                parts.append(('e', s[i + 2:end]))
                i = end + 1
                continue
            m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', s[i + 1:])
            if m:
                if buf:
                    parts.append(('t', buf))
                    buf = ''
                parts.append(('e', m.group(0)))
                i += 1 + len(m.group(0))
                continue
        buf += c
        i += 1
    if buf:
        parts.append(('t', buf))
    return i, {'raw': raw, 'triple': triple, 'quote': q, 'parts': parts}


def is_people_text(template):
    plain = re.sub(r'\{\d+\}', '', template)
    if not re.search(r'[A-Za-z]', plain):
        return False
    if re.search(r'://|^assets/|^packages/|\.(png|svg|ttf|json|html|csv)$|@|cafepos-|\{|\}', plain):
        return False
    if re.fullmatch(r'[a-z0-9_.\-/:]+', plain):
        return False
    stripped = plain.strip()
    return ' ' in stripped or bool(re.match(r'[A-Z]', stripped)) or '…' in plain


def transform(src, rel):
    out = []
    i = 0
    n = len(src)
    wraps = {}
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(src[i:j]); i = j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i)
            j = n if j < 0 else j + 2
            out.append(src[i:j]); i = j; continue
        is_r = c == 'r' and i + 1 < n and src[i + 1] in '\'"' and not (i > 0 and (src[i - 1].isalnum() or src[i - 1] == '_'))
        if c in '\'"' or is_r:
            # adjacent literals form one string
            start = i
            pieces = []
            j = i
            while True:
                j, info = scan_string(src, j)
                pieces.append(info)
                k = skip_ws_comments(src, j)
                if k < n and (src[k] in '\'"' or (src[k] == 'r' and k + 1 < n and src[k + 1] in '\'"')):
                    j = k
                    continue
                break
            end = j
            original = src[start:end]
            repl = maybe_wrap(src, start, end, pieces, rel)
            if repl is None:
                out.append(original)
            else:
                out.append(repl)
                wraps[repl] = original
            i = end
            continue
        out.append(c)
        i += 1
    return ''.join(out), wraps


def maybe_wrap(src, start, end, pieces, rel):
    if any(p['raw'] or p['triple'] for p in pieces):
        return None
    before = src[max(0, start - 80):start]
    after = src[end:end + 12]
    line_start = src.rfind('\n', 0, start) + 1
    line = src[line_start:start].strip()
    if line.startswith(('import', 'export', 'part', '@')):
        return None
    if BAD_BEFORE.search(before) or INDEX_BEFORE.search(before):
        return None
    a = after.lstrip()
    if a.startswith(('=>', '==', '!=', '||')):
        return None
    if a.startswith(':') and re.search(r'[\{,\(\[]\s*$', before):
        return None  # map key
    # template
    template = ''
    args = []
    for p in pieces:
        for kind, val in p['parts']:
            if kind == 't':
                if p['quote'] == '"':
                    val = val.replace("\\\"", '"').replace("'", "\\'")
                template += val
            else:
                template += '{%d}' % len(args)
                inner, _ = transform(val, rel)
                args.append(inner.strip())
    if not is_people_text(template):
        return None
    plain_value = template.replace("\\'", "'")
    if plain_value in DATA_VALUES and not DISPLAY_CTX.search(before):
        return None
    lit = "'" + template + "'"
    if args:
        return 'tr(%s, [%s])' % (lit, ', '.join(args))
    return 'tr(%s)' % lit


def dart_files():
    for d, _, fs in os.walk(LIB):
        for f in fs:
            if f.endswith('.dart'):
                p = os.path.join(d, f)
                yield p, os.path.relpath(p, ROOT)


IMPORT_LINE = "import 'package:pos_app/core/i18n/tr.dart';\n"
WRAPS_FILE = os.path.join(ROOT, 'build', 'i18n_wraps.json')


def add_import(src):
    if IMPORT_LINE in src:
        return src
    m = list(re.finditer(r'^import .*;\n', src, re.M))
    if m:
        pos = m[-1].end()
        return src[:pos] + IMPORT_LINE + src[pos:]
    return IMPORT_LINE + src


def cmd_wrap():
    all_wraps = {}
    for p, rel in dart_files():
        if excluded(rel):
            continue
        src = open(p).read()
        new, wraps = transform(src, rel)
        if wraps:
            new = add_import(new)
            open(p, 'w').write(new)
            all_wraps[rel] = wraps
            print(rel, len(wraps))
    os.makedirs(os.path.dirname(WRAPS_FILE), exist_ok=True)
    json.dump(all_wraps, open(WRAPS_FILE, 'w'), ensure_ascii=False, indent=0)


def matching_paren(s, i):
    """s[i] == '(' / '[' / '{'. Return index after the matching close."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = [pairs[s[i]]]
    i += 1
    while i < len(s) and stack:
        c = s[i]
        if c in '\'"' or (c == 'r' and i + 1 < len(s) and s[i + 1] in '\'"'):
            i, _ = scan_string(s, i)
            continue
        if s.startswith('//', i):
            i = s.find('\n', i); continue
        if c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
        i += 1
    return i


def const_extent(s, c):
    """Extent of the expression introduced by the const keyword at c."""
    i = c + 5
    i = skip_ws_comments(s, i)
    # const <T>[...] / const [..] / const {..} / const Foo.bar<T>(...)
    while i < len(s) and s[i] not in '([{;=,':
        if s[i] == '<':
            depth = 0
            while i < len(s):
                if s[i] == '<': depth += 1
                elif s[i] == '>':
                    depth -= 1
                    if depth == 0:
                        i += 1; break
                i += 1
            continue
        i += 1
    if i < len(s) and s[i] in '([{':
        return matching_paren(s, i)
    return None  # declaration form: const x = ...


def revert_at(s, off, wraps):
    k = s.rfind('tr(', 0, off + 1)
    while k >= 0:
        if (k == 0 or not (s[k - 1].isalnum() or s[k - 1] == '_')):
            e = matching_paren(s, k + 2)
            if k <= off < e:
                call = s[k:e]
                if call in wraps:
                    return s[:k] + wraps[call] + s[e:], True
                return s, False
        k = s.rfind('tr(', 0, k)
    return s, False


def cmd_fixconst():
    wraps_all = json.load(open(WRAPS_FILE))
    for it in range(40):
        r = subprocess.run(['dart', 'analyze', '--format=machine', 'lib'], cwd=ROOT, capture_output=True, text=True)
        errs = [l.split('|') for l in (r.stdout + r.stderr).splitlines() if l.startswith('ERROR|')]
        if not errs:
            print('clean after', it, 'rounds')
            return
        print('round', it, len(errs), 'errors')
        by_file = {}
        for e in errs:
            by_file.setdefault(e[3], []).append(e)
        changed = False
        for path, es in by_file.items():
            rel = os.path.relpath(path, ROOT)
            s = open(path).read()
            lines = s.split('\n')
            offs = []
            for e in es:
                ln, col = int(e[4]), int(e[5])
                offs.append((sum(len(x) + 1 for x in lines[:ln - 1]) + col - 1, e[2], e[7] if len(e) > 7 else ''))
            # process from the end so offsets stay valid; one fix per region per round
            done_ranges = []
            for off, code, msg in sorted(offs, reverse=True):
                if any(a <= off < b for a, b in done_ranges):
                    continue
                code_l = code.lower()
                if code_l in ('non_constant_default_value',):
                    s, ok = revert_at(s, off, wraps_all.get(rel, {}))
                    changed |= ok
                    continue
                # nearest enclosing const keyword
                fixed = False
                for m in reversed(list(re.finditer(r'\bconst\b', s[:off + 1]))):
                    c = m.start()
                    ext = const_extent(s, c)
                    if ext is None:
                        # declaration: `const x = ...` / `static const x = ...`
                        stmt_end = s.find(';', off)
                        if c < off <= stmt_end:
                            pre = s[s.rfind('\n', 0, c) + 1:c]
                            if 'static' in pre or not pre.startswith((' ', '\t')):
                                s, ok = revert_at(s, off, wraps_all.get(rel, {}))
                                changed |= ok
                            else:
                                s = s[:c] + 'final' + s[c + 5:]
                                changed = True
                            fixed = True
                            break
                        continue
                    if c < off < ext:
                        s = s[:c] + s[c + 5:].lstrip(' ')
                        done_ranges.append((c, ext))
                        changed = True
                        fixed = True
                        break
                if not fixed:
                    s, ok = revert_at(s, off, wraps_all.get(rel, {}))
                    if ok:
                        changed = True
                    else:
                        print('  unresolved', rel, off, code, msg)
            open(path, 'w').write(s)
        if not changed:
            print('stuck')
            for e in errs[:30]:
                print(' ', e[3], e[4], e[2], e[7] if len(e) > 7 else '')
            return


def cmd_keys():
    keys = set()
    for p, rel in dart_files():
        s = open(p).read()
        for m in re.finditer(r"(?<![\w])tr\('((?:[^'\\]|\\.)*)'", s):
            keys.add(m.group(1).encode().decode('unicode_escape').encode('latin1').decode('utf-8') if '\\u' in m.group(1) else m.group(1).replace("\\'", "'").replace('\\$', '$').replace('\\n', '\n').replace('\\\\', '\\'))
    print(json.dumps(sorted(keys), ensure_ascii=False, indent=0))


if __name__ == '__main__':
    {'wrap': cmd_wrap, 'fixconst': cmd_fixconst, 'keys': cmd_keys}[sys.argv[1]]()
