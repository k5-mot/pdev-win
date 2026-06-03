#!/usr/bin/env python3
"""Split extracted Markdown into translation chunks for constrained-context LLMs."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


FENCE_RE = re.compile(r"^\s*```")
HEADING_RE = re.compile(r"^#{1,6}\s+")
TABLE_RE = re.compile(r"^\s*\|.*\|\s*$")
LIST_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")


def blocks(markdown: str) -> list[str]:
    lines = markdown.splitlines(keepends=True)
    out: list[str] = []
    current: list[str] = []
    in_fence = False
    in_table = False

    def flush() -> None:
        nonlocal current
        if current:
            out.append("".join(current))
            current = []

    for line in lines:
        if FENCE_RE.match(line):
            current.append(line)
            in_fence = not in_fence
            if not in_fence:
                flush()
            continue
        if in_fence:
            current.append(line)
            continue

        is_table = bool(TABLE_RE.match(line))
        if is_table:
            if not in_table:
                flush()
                in_table = True
            current.append(line)
            continue
        if in_table:
            flush()
            in_table = False

        if HEADING_RE.match(line):
            flush()
            current.append(line)
            continue

        if not line.strip():
            current.append(line)
            flush()
            continue

        if LIST_RE.match(line) and current and not current[-1].strip():
            flush()
        current.append(line)

    flush()
    return out


def split_chunks(parts: list[str], max_chars: int) -> list[str]:
    chunks: list[str] = []
    current: list[str] = []
    current_len = 0

    for part in parts:
        part_len = len(part)
        if current and current_len + part_len > max_chars:
            chunks.append("".join(current).rstrip() + "\n")
            current = []
            current_len = 0
        current.append(part)
        current_len += part_len

    if current:
        chunks.append("".join(current).rstrip() + "\n")
    return chunks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_md", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--max-chars", type=int, default=20000)
    args = parser.parse_args()

    source = args.input_md.read_text(encoding="utf-8")
    chunks = split_chunks(blocks(source), args.max_chars)
    en_dir = args.output_dir / "en"
    ja_dir = args.output_dir / "ja"
    en_dir.mkdir(parents=True, exist_ok=True)
    ja_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source_markdown": str(args.input_md),
        "max_chars": args.max_chars,
        "chunks": [],
        "notes": [
            "Translate each en/chunk-NNNN.md into ja/chunk-NNNN.ja.md.",
            "Concatenate Japanese chunks in manifest order after translation.",
        ],
    }

    for index, chunk in enumerate(chunks, start=1):
        en_name = f"chunk-{index:04d}.md"
        ja_name = f"chunk-{index:04d}.ja.md"
        (en_dir / en_name).write_text(chunk, encoding="utf-8")
        (ja_dir / ja_name).write_text(chunk, encoding="utf-8")
        manifest["chunks"].append(
            {
                "index": index,
                "source": f"en/{en_name}",
                "translation": f"ja/{ja_name}",
                "source_chars": len(chunk),
            }
        )

    (args.output_dir / "chunks-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
