#!/usr/bin/env python3
"""Validate shipped UI translations, plural forms and format arguments."""
import json
from pathlib import Path
import re
import sys

catalog = Path(__file__).resolve().parent.parent / 'Shared/Resources/Localizable.xcstrings'
locales = ('en', 'es', 'zh-Hans', 'zh-Hant', 'ja', 'fr', 'de')
errors = []

def units(node):
    if 'stringUnit' in node:
        yield node['stringUnit']
    else:
        for value in node.values():
            if isinstance(value, dict):
                yield from units(value)

def arguments(text):
    # Preserve type, multiplicity and argument position, including reordering.
    matches = re.findall(r'%(?:(\d+)\$)?(lld|ld|lu|d|u|@)', text)
    return sorted((int(position) if position else index + 1, kind)
                  for index, (position, kind) in enumerate(matches))

strings = json.loads(catalog.read_text())['strings']
for key, entry in strings.items():
    if entry.get('shouldTranslate') is False or entry.get('extractionState') == 'stale':
        continue
    for locale in locales:
        translation = entry.get('localizations', {}).get(locale, {})
        values = list(units(translation))
        # English falls back to the catalog key when no plural/ordering is needed.
        if locale == 'en' and not values:
            continue
        if not values:
            errors.append(f'{locale}: missing {key}')
        for unit in values:
            value = unit.get('value', '')
            if not value or unit.get('state') != 'translated':
                errors.append(f'{locale}: incomplete {key}')
            if arguments(value) != arguments(key):
                errors.append(f'{locale}: format arguments differ: {key}')
        plural = translation.get('variations', {}).get('plural')
        if plural and 'other' not in plural:
            errors.append(f'{locale}: plural missing other: {key}')
if errors:
    print('\n'.join(errors[:30]), file=sys.stderr)
    sys.exit(f'{len(errors)} localization errors')
print(f'Validated {len(strings)} keys in {len(locales)} interface languages.')
