#!/usr/bin/env python3
"""Prepare or validate a Markdown+PNG Japanese translation workspace."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

IMAGE_RE = re.compile(r"!\[[^\]]*]\(([^)]+)\)")


def image_refs(markdown: str) -> list[str]:
    return [m.group(1).strip().strip('"') for m in IMAGE_RE.finditer(markdown)]


def prepare(input_md: Path, output_dir: Path, glossary: Path | None = None) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    source = input_md.read_text(encoding="utf-8")
    refs = image_refs(source)
    copied = []
    for ref in refs:
        if "://" in ref or ref.startswith("#"):
            continue
        src = (input_md.parent / ref).resolve()
        dst = output_dir / ref
        if src.exists() and src.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            copied.append(ref)
    copied_glossary = None
    if glossary and glossary.exists():
        glossary_dst = output_dir / glossary.name
        shutil.copy2(glossary, glossary_dst)
        copied_glossary = glossary.name
    out_md = output_dir / "document.ja.md"
    out_md.write_text(source, encoding="utf-8")
    manifest = {
        "source_markdown": str(input_md),
        "japanese_markdown": str(out_md),
        "image_refs": refs,
        "copied_assets": copied,
        "proper_noun_glossary": copied_glossary,
        "notes": ["Translate prose in document.ja.md; preserve Markdown syntax and image paths."],
    }
    (output_dir / "translation-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def check(markdown_path: Path) -> dict:
    text = markdown_path.read_text(encoding="utf-8")
    missing = []
    for ref in image_refs(text):
        if "://" not in ref and not ref.startswith("#") and not (markdown_path.parent / ref).exists():
            missing.append(ref)
    fenced_count = text.count("```")
    result = {
        "markdown": str(markdown_path),
        "missing_image_refs": missing,
        "unbalanced_fenced_code_blocks": fenced_count % 2 != 0,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_md", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--glossary", type=Path, default=Path(__file__).resolve().parents[1] / "proper_noun_glossary.csv")
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    if args.check:
        result = check(args.check)
        return 1 if result["missing_image_refs"] or result["unbalanced_fenced_code_blocks"] else 0
    if not args.input_md or not args.output_dir:
        parser.error("input_md and output_dir are required unless --check is used")
    manifest = prepare(args.input_md, args.output_dir, args.glossary)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
