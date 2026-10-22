#!/usr/bin/env python3
"""Verify the unchanged pinned Apex/cmark/libyaml source snapshot."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'Vendor/Apex'
manifest = json.loads((root / 'SOURCE-HASHES.json').read_text())
for name, expected in manifest.items():
    path = root / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'Vendored source differs from pinned upstream: {name}')
print(f'Verified {len(manifest)} unchanged pinned Apex/cmark/libyaml files.')
