#!/usr/bin/env python3
"""Validate localized Nepal medicines datasets before release.

Checks:
- JSON syntax
- canonical + backward-compatible key presence
- duplicate ids/names
- pregnancy_category normalization
- provenance metadata presence
- canonical alias consistency (uses == indications, etc.)
- high-risk clinical regressions flagged during review
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = [
    ROOT / 'nepal_medicines.json',
    ROOT / 'nepal_medicines_e.json',
    ROOT / 'nepal_medicines_hi.json',
    ROOT / 'nepal_medicines_ne.json',
]
REQUIRED_KEYS = {
    'id',
    'name',
    'generic_name',
    'category',
    'uses',
    'indications',
    'side_effects',
    'adverse_effects',
    'dosage',
    'dosage_schedule',
    'precautions',
    'contraindications',
    'interactions',
    'pregnancy_category',
    'pregnancy_category_notes',
    'manufacturer_info',
    'brand_notes',
    'source',
    'reviewed_on',
    'guideline_version',
    'release_status',
}
VALID_PREGNANCY = {'A', 'B', 'C', 'D', 'X', 'N/A', 'unknown', ''}
VALID_RELEASE_STATUS = {'ready', 'needs_review'}
NAME_BLACKLIST = {
    'GLYCERYL TRINATRE',
    'ISOSOBIDE MONONITRATES',
    'TOFACUTINIB',
    'ACELECOFENAC',
    'HYDROCHLORTHIAZIDE',
}
ISO_DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def fail(errors: list[str]) -> int:
    for err in errors:
        print(f'ERROR: {err}')
    return 1


def validate_file(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        records = json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        return [f'{path.name}: invalid JSON: {exc}']

    if not isinstance(records, list):
        return [f'{path.name}: top-level JSON must be a list']

    seen_ids: set[str] = set()
    seen_names: set[str] = set()

    for index, record in enumerate(records):
        label = f'{path.name}[{index}]'
        if not isinstance(record, dict):
            errors.append(f'{label}: record must be an object')
            continue

        missing = sorted(key for key in REQUIRED_KEYS if key not in record)
        if missing:
            errors.append(f'{label}: missing keys: {", ".join(missing)}')

        rid = str(record.get('id') or '').strip()
        name = str(record.get('name') or '').strip()
        if not rid:
            errors.append(f'{label}: id is empty')
        elif rid in seen_ids:
            errors.append(f'{label}: duplicate id {rid}')
        else:
            seen_ids.add(rid)

        if not name:
            errors.append(f'{label}: name is empty')
        elif name in seen_names:
            errors.append(f'{label}: duplicate name {name}')
        else:
            seen_names.add(name)

        upper_name = name.upper()
        for typo in NAME_BLACKLIST:
            if typo in upper_name:
                errors.append(f'{label}: misspelled medicine name still present: {name}')

        pregnancy_category = str(record.get('pregnancy_category') or '').strip()
        if pregnancy_category not in VALID_PREGNANCY:
            errors.append(
                f'{label}: invalid pregnancy_category {pregnancy_category!r}'
            )

        reviewed_on = str(record.get('reviewed_on') or '').strip()
        if reviewed_on and not ISO_DATE.match(reviewed_on):
            errors.append(f'{label}: reviewed_on must be YYYY-MM-DD, got {reviewed_on!r}')

        for key in ('source', 'reviewed_on', 'guideline_version'):
            value = str(record.get(key) or '').strip()
            if not value:
                errors.append(f'{label}: {key} must not be empty')

        if str(record.get('release_status') or '').strip() not in VALID_RELEASE_STATUS:
            errors.append(f"{label}: release_status must be one of {sorted(VALID_RELEASE_STATUS)}")

        # Canonical aliases should stay aligned so old and new consumers read the same value.
        alias_pairs = [
            ('uses', 'indications'),
            ('side_effects', 'adverse_effects'),
            ('dosage', 'dosage_schedule'),
        ]
        for legacy_key, canonical_key in alias_pairs:
            legacy_value = str(record.get(legacy_key) or '').strip()
            canonical_value = str(record.get(canonical_key) or '').strip()
            if legacy_value != canonical_value:
                errors.append(
                    f'{label}: {legacy_key} and {canonical_key} must match for backward compatibility'
                )

        manufacturer_info = str(record.get('manufacturer_info') or '').strip()
        brand_notes = str(record.get('brand_notes') or '').strip()
        if manufacturer_info and brand_notes not in {manufacturer_info, 'N/A'}:
            errors.append(f'{label}: brand_notes should mirror manufacturer_info when present')

        if upper_name == 'LEVONORGESTREL':
            dosage = str(record.get('dosage_schedule') or '').lower()
            if '1.5' not in dosage:
                errors.append(f'{label}: LEVONORGESTREL dosage must contain the single-dose strength 1.5')
            if '1.5 g' in dosage:
                errors.append(f'{label}: LEVONORGESTREL dosage must not contain 1.5 g')

        if upper_name == 'PARACETAMOL':
            precautions = str(record.get('precautions') or '')
            if '>0.4 g/day' in precautions or '0.4 g/day' in precautions or '०.४ ग्राम/दिन' in precautions:
                errors.append(f'{label}: PARACETAMOL precautions still contain the 0.4 g/day threshold')

        precautions = str(record.get('precautions') or '')
        if ('उत्पादन गरेको' in precautions or 'manufactured by' in precautions.lower()) and not manufacturer_info:
            errors.append(f'{label}: manufacturer text still appears in precautions without manufacturer_info')

    return errors


def main() -> int:
    all_errors: list[str] = []
    for path in FILES:
        all_errors.extend(validate_file(path))
    if all_errors:
        return fail(all_errors)
    print('All medicine datasets passed validation.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
