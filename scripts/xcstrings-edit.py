#!/usr/bin/env python3
"""Add or remove single entries in an Xcode string catalog without reformatting the rest.

The catalog mixes `"key" : value` and `"key": value` spacing from earlier tools, so a full
json.dump rewrite would touch thousands of unrelated lines. This edits only the entry's lines.

Usage:
  scripts/xcstrings-edit.py remove <catalog> <key> [<key> ...]
  scripts/xcstrings-edit.py add <catalog> <after-key> <key> <json-file>
      <json-file>: {"zh-Hans": "...", "en": "...", ...} (stringUnit values, all translated)
  scripts/xcstrings-edit.py unused <catalog> <swift-root>
      lists keys no Swift file under <swift-root> mentions as a string literal
"""
import json
import os
import re
import sys


def entry_span(lines, key):
    """Line range [start, end) of a top-level entry (4-space indent) in the catalog."""
    head = re.compile(r'^    ' + re.escape(json.dumps(key, ensure_ascii=False)) + r'\s*:\s*\{\s*$')
    for start, line in enumerate(lines):
        if head.match(line):
            depth = 0
            for end in range(start, len(lines)):
                depth += lines[end].count('{') - lines[end].count('}')
                if depth == 0:
                    return start, end + 1
    raise SystemExit(f"entry not found: {key}")


def render_entry(key, values, trailing_comma):
    entry = {
        "extractionState": "manual",
        "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": value}}
            for lang, value in sorted(values.items())
        },
    }
    body = json.dumps(entry, ensure_ascii=False, indent=2, separators=(',', ' : '))
    body = '\n'.join('    ' + line for line in body.split('\n')).lstrip()
    text = '    ' + json.dumps(key, ensure_ascii=False) + ' : ' + body
    return (text + (',' if trailing_comma else '')).split('\n')


def main():
    command, path = sys.argv[1], sys.argv[2]
    with open(path, encoding='utf-8') as handle:
        lines = handle.read().split('\n')
    catalog = json.loads('\n'.join(lines))

    if command == 'remove':
        for key in sys.argv[3:]:
            start, end = entry_span(lines, key)
            removed_last = not lines[end - 1].rstrip().endswith(',')
            del lines[start:end]
            if removed_last:
                # The entry before it is now the last one: drop its trailing comma.
                lines[start - 1] = lines[start - 1].rstrip().rstrip(',')
    elif command == 'add':
        after, key, values_file = sys.argv[3], sys.argv[4], sys.argv[5]
        if key in catalog['strings']:
            raise SystemExit(f"already present: {key}")
        with open(values_file, encoding='utf-8') as handle:
            values = json.load(handle)
        _, end = entry_span(lines, after)
        anchor_has_comma = lines[end - 1].rstrip().endswith(',')
        if not anchor_has_comma:
            lines[end - 1] = lines[end - 1].rstrip() + ','
        lines[end:end] = render_entry(key, values, trailing_comma=anchor_has_comma)
    elif command == 'unused':
        root = sys.argv[3]
        corpus = []
        for directory, _, files in os.walk(root):
            for name in files:
                if name.endswith('.swift'):
                    with open(os.path.join(directory, name), encoding='utf-8') as handle:
                        corpus.append(handle.read())
        corpus = '\n'.join(corpus)
        for key in sorted(catalog['strings']):
            if json.dumps(key, ensure_ascii=False) not in corpus:
                print(key)
        return
    else:
        raise SystemExit(__doc__)

    text = '\n'.join(lines)
    json.loads(text)  # still valid JSON
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


if __name__ == '__main__':
    main()
