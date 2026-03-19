"""
translate_medicines.py  —  Swasthall
─────────────────────────────────────
Produces 3 files from nepal_medicines.json:
  nepal_medicines_en.json  → replace assets/data/nepal_medicines.json
  nepal_medicines_ne.json  → assets/data/nepal_medicines_ne.json
  nepal_medicines_hi.json  → assets/data/nepal_medicines_hi.json

Verified field coverage (759 entries):
  uses              100%   ← indications / uses / clues_symptoms (poisoning)
  side_effects       97%   ← adverse_effects / risk_assessment (poisoning)
  dosage             98%   ← dosage_schedule / dosage_form_strength
  precautions        87%   ← precautions / patient_info / management_protocol
  contraindications  83%   ← contraindications / investigations (poisoning)
  interactions       41%   ← only present for 312 entries — that's the source data
  pregnancy_category 28%   ← only present for 210 entries — that's the source data

HOW TO RUN:
  1. Place this file next to nepal_medicines.json
  2. pip install requests
  3. python translate_medicines.py
  Safe to interrupt — resumes from where it stopped.
"""

import json, time, os, requests  # pyright: ignore[reportMissingModuleSource]
from urllib.parse import quote

INPUT_FILE  = "nepal_medicines.json"
OUTPUT_EN   = "nepal_medicines_en.json"
OUTPUT_NE   = "nepal_medicines_ne.json"
OUTPUT_HI   = "nepal_medicines_hi.json"
LANGUAGES   = {"ne": OUTPUT_NE, "hi": OUTPUT_HI}

# Fields to translate (name/generic_name/category/pregnancy_category stay English)
TRANSLATE_FIELDS = [
    "uses", "side_effects", "dosage",
    "precautions", "contraindications", "interactions",
]

DELAY      = 0.35   # seconds between Google Translate calls
SAVE_EVERY = 10     # save progress every N entries


# ── helpers ──────────────────────────────────────────────────────────────────

def translate(text: str, lang: str) -> str:
    """Translate text using Google's free endpoint."""
    if not text or text.strip() in ("", "N/A"):
        return text
    try:
        url = (
            "https://translate.googleapis.com/translate_a/single"
            f"?client=gtx&sl=en&tl={lang}&dt=t&q={quote(text)}"
        )
        r = requests.get(url, timeout=15)
        if r.status_code == 200:
            return "".join(p[0] for p in r.json()[0] if p and p[0]).strip()
        print(f"  ⚠ HTTP {r.status_code} — keeping original")
    except Exception as e:
        print(f"  ⚠ {e} — keeping original")
    return text


def best(entry: dict, keys: list, fallback="N/A") -> str:
    """Return first non-empty value from a priority list of keys."""
    for k in keys:
        v = entry.get(k)
        if v is None:
            continue
        if isinstance(v, list):
            v = " ".join(str(x).strip() for x in v if str(x).strip())
        v = str(v).strip()
        if v and v.lower() != "n/a":
            return v
    return fallback


def normalize(entry: dict) -> dict:
    """
    Map every possible source key to one clean 10-field schema.
    Poisoning entries (clues_symptoms / management_protocol) get
    their unique fields remapped to the shared schema so Flutter
    can display them without any special-case logic.
    """
    is_poisoning = "clues_symptoms" in entry or "management_protocol" in entry

    if is_poisoning:
        return {
            "name":               best(entry, ["name"], ""),
            "generic_name":       "",
            "category":           best(entry, ["category"], "Antidotes & Poisoning"),
            # remap poisoning-specific fields into the shared schema
            "uses":               best(entry, ["clues_symptoms"]),
            "side_effects":       best(entry, ["risk_assessment"]),
            "dosage":             best(entry, ["antidote_dosage", "antidote_name"]),
            "precautions":        best(entry, ["management_protocol"]),
            "contraindications":  best(entry, ["investigations"]),
            "interactions":       "N/A",
            "pregnancy_category": "N/A",
        }

    return {
        "name":               best(entry, ["name", "brand_name"], ""),
        "generic_name":       best(entry, ["generic_name", "generic", "salt_name"], ""),
        "category":           best(entry, ["category", "sub_category", "type"], ""),
        "uses":               best(entry, ["uses", "indications", "indications_and_usage", "use", "purpose"]),
        "side_effects":       best(entry, [
                                  "adverse_effects", "adverse_effect", "side_effects",
                                  "adverse_drug_reaction", "adverse_drug_reactions", "adverse_reactions",
                              ]),
        "dosage":             best(entry, ["dosage_schedule", "dosage", "dose", "dosage_form_strength",
                                           "dosage_and_administration"]),
        "precautions":        best(entry, ["precautions", "patient_info", "nepal_brand_notes", "notes"]),
        "contraindications":  best(entry, ["contraindications", "contraindication"]),
        "interactions":       best(entry, ["interactions"]),
        "pregnancy_category": best(entry, ["pregnancy_category"]),
    }


def save(path: str, data: list):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    print(f"Loading {INPUT_FILE}...")
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        raw = json.load(f)
    total = len(raw)
    print(f"  {total} entries found.\n")

    # ── Step 1: produce clean English JSON ───────────────────
    print("Normalizing English schema...")
    normalized = [normalize(e) for e in raw]
    save(OUTPUT_EN, normalized)
    print(f"✅ {OUTPUT_EN} ({os.path.getsize(OUTPUT_EN)//1024} KB)\n")

    # Quick coverage report
    fields = ["uses","side_effects","dosage","precautions","contraindications","interactions","pregnancy_category"]
    for f in fields:
        count = sum(1 for r in normalized if r[f] != "N/A")
        print(f"  {f:22s}: {count}/{total} ({count/total*100:.0f}%)")
    print()

    # ── Step 2: translate to each language ───────────────────
    for lang_code, output_file in LANGUAGES.items():
        lang_name = "Nepali" if lang_code == "ne" else "Hindi"
        print("=" * 55)
        print(f"Translating → {lang_name} ({lang_code})  |  output: {output_file}")
        print("=" * 55)

        # Resume support
        if os.path.exists(output_file):
            with open(output_file, "r", encoding="utf-8") as f:
                results = json.load(f)
            start = len(results)
            print(f"  Resuming from entry {start + 1}...\n")
        else:
            results, start = [], 0

        for i, entry in enumerate(normalized[start:], start=start):
            translated = {
                # Identity fields — always kept in English
                "name":               entry["name"],
                "generic_name":       entry["generic_name"],
                "category":           entry["category"],
                "pregnancy_category": entry["pregnancy_category"],
            }
            for field in TRANSLATE_FIELDS:
                original = entry.get(field, "N/A")
                if original and original != "N/A":
                    translated[field] = translate(original, lang_code)
                    time.sleep(DELAY)
                else:
                    translated[field] = "N/A"

            results.append(translated)
            pct = (i + 1) / total * 100
            print(f"  [{i+1}/{total}] {pct:.1f}% — {entry['name']}")

            if (i + 1) % SAVE_EVERY == 0:
                save(output_file, results)
                print(f"  ✓ Progress saved ({i+1} entries)")

        save(output_file, results)
        print(f"\n✅ {output_file} ({os.path.getsize(output_file)//1024} KB)\n")

    print("=" * 55)
    print("ALL DONE. Copy these to your Flutter project:")
    print(f"  {OUTPUT_EN}  →  assets/data/nepal_medicines.json")
    print(f"  {OUTPUT_NE}  →  assets/data/nepal_medicines_ne.json")
    print(f"  {OUTPUT_HI}  →  assets/data/nepal_medicines_hi.json")


if __name__ == "__main__":
    main()