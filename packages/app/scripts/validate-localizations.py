#!/usr/bin/env python3
"""Validate catalog coverage and typed Foundation interpolation placeholders."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/AeroKitCore/Resources"
LANGUAGES = ("en", "ja", "zh-Hans", "ko", "es", "fr", "de")
FORMAT = re.compile(r"%(?:(\d+)\$)?(lld|llu|ld|lu|d|u|f|g|@|%)")


def arguments(text):
    result = {}
    next_position = 1
    consumed = set()
    for match in FORMAT.finditer(text):
        consumed.update(range(match.start(), match.end()))
        position, kind = match.groups()
        if kind == "%":
            continue
        index = int(position) if position else next_position
        if not position:
            next_position += 1
        if index in result and result[index] != kind:
            raise ValueError(f"Conflicting argument types in {text!r}")
        result[index] = kind
    if any(char == "%" and index not in consumed for index, char in enumerate(text)):
        raise ValueError(f"Unsupported format placeholder in {text!r}")
    return result, Counter(match.group(2) for match in FORMAT.finditer(text))


def read_catalog(language):
    path = RESOURCES / f"{language}.lproj/Localizable.strings"
    output = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)], text=True)
    catalog = json.loads(output)
    # plutil accepts duplicate keys, which would silently discard a translation.
    definitions = re.findall(r'^\s*"(?:[^"\\]|\\.)*"\s*=', path.read_text(), re.MULTILINE)
    if len(definitions) != len(catalog):
        raise ValueError(f"Duplicate or malformed keys in {path}")
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extracted", type=Path, help="Swift compiler .stringsdata output directory")
    args = parser.parse_args()
    catalogs = {language: read_catalog(language) for language in LANGUAGES}
    keys = set(catalogs["en"])
    if args.extracted:
        extracted = set()
        files = list(args.extracted.glob("*.stringsdata"))
        if not files:
            raise ValueError("No compiler extraction files found")
        for path in files:
            table = json.loads(path.read_text()).get("tables", {}).get("Localizable", [])
            extracted.update(entry["key"] for entry in table)
        if missing := extracted - keys:
            raise ValueError(f"Untranslated source keys: {sorted(missing)}")
    for language, catalog in catalogs.items():
        if set(catalog) != keys:
            raise ValueError(f"{language}: missing {keys - catalog.keys()}, extra {catalog.keys() - keys}")
        for key, value in catalog.items():
            if not value.strip():
                raise ValueError(f"{language}: empty translation for {key!r}")
            if arguments(key) != arguments(value):
                raise ValueError(f"{language}: mismatched placeholders: {key!r} -> {value!r}")
    print(f"Validated {len(keys)} keys across {len(LANGUAGES)} languages; typed placeholders match.")


if __name__ == "__main__":
    main()
