#!/usr/bin/env python3
"""Run lightweight quality checks for Japanese Markdown translations."""

from __future__ import annotations

import argparse
import csv
import json
import re
from difflib import SequenceMatcher
from pathlib import Path


IMAGE_RE = re.compile(r"!\[[^\]]*]\(([^)]+)\)")
CODE_BLOCK_RE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE_RE = re.compile(r"`[^`]*`")
URL_RE = re.compile(r"https?://\S+")
ENGLISH_SENTENCE_RE = re.compile(r"\b[A-Za-z][A-Za-z0-9,;:'\"() -]{30,}[.!?]")
POLITE_RE = re.compile(r"(です|ます|でした|ました|ください)")
PLAIN_RE = re.compile(r"(である|する。|した。|される。|となる。|できる。)")


def image_refs(markdown: str) -> list[str]:
    return [m.group(1).strip().strip('"') for m in IMAGE_RE.finditer(markdown)]


def strip_ignored(markdown: str) -> str:
    text = CODE_BLOCK_RE.sub("", markdown)
    text = INLINE_CODE_RE.sub("", text)
    text = URL_RE.sub("", text)
    text = re.sub(r"!\[[^\]]*]\([^)]+\)", "", text)
    return text


def glossary_entries(path: Path | None) -> list[dict[str, str]]:
    if not path or not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return [
            row
            for row in csv.DictReader(handle)
            if row.get("english", "").strip() and row.get("japanese", "").strip()
        ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_md", type=Path)
    parser.add_argument("translated_md", type=Path)
    parser.add_argument("--glossary", type=Path)
    args = parser.parse_args()

    source = args.source_md.read_text(encoding="utf-8")
    translated = args.translated_md.read_text(encoding="utf-8")
    source_visible = strip_ignored(source)
    translated_visible = strip_ignored(translated)
    warnings: list[dict[str, str]] = []

    source_compact = re.sub(r"\s+", " ", source_visible).strip()
    translated_compact = re.sub(r"\s+", " ", translated_visible).strip()
    if source_compact and translated_compact:
        similarity = SequenceMatcher(None, source_compact, translated_compact).ratio()
        if similarity >= 0.85:
            warnings.append(
                {
                    "type": "placeholder_not_translated",
                    "detail": f"source and translation are {similarity:.0%} similar",
                }
            )

    source_images = set(image_refs(source))
    translated_images = set(image_refs(translated))
    for ref in sorted(source_images - translated_images):
        warnings.append({"type": "missing_image_ref", "detail": ref})
    for ref in sorted(translated_images - source_images):
        warnings.append({"type": "new_or_changed_image_ref", "detail": ref})

    for row in glossary_entries(args.glossary):
        english = row["english"].strip()
        japanese = row["japanese"].strip()
        if english in source and japanese not in translated:
            warnings.append(
                {
                    "type": "glossary_missing",
                    "detail": f"{english} -> {japanese}",
                }
            )

    polite_count = len(POLITE_RE.findall(translated_visible))
    plain_count = len(PLAIN_RE.findall(translated_visible))
    if polite_count and plain_count and min(polite_count, plain_count) >= 5:
        warnings.append(
            {
                "type": "mixed_style",
                "detail": f"polite_markers={polite_count}, plain_markers={plain_count}",
            }
        )

    leftovers = ENGLISH_SENTENCE_RE.findall(translated_visible)
    for sentence in leftovers[:20]:
        warnings.append({"type": "possible_untranslated_english", "detail": sentence[:160]})

    source_len = len(source_visible.strip())
    translated_len = len(translated_visible.strip())
    if source_len and translated_len / source_len < 0.35:
        warnings.append(
            {
                "type": "length_mismatch",
                "detail": f"source_chars={source_len}, translated_chars={translated_len}",
            }
        )

    result = {
        "source_markdown": str(args.source_md),
        "translated_markdown": str(args.translated_md),
        "warnings": warnings,
        "warning_count": len(warnings),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if warnings else 0


if __name__ == "__main__":
    raise SystemExit(main())
