#!/usr/bin/env python3
"""Orchestrate DOCX/PDF extraction and Japanese Markdown workspace preparation."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> None:
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--skills-root", type=Path, default=Path.home() / ".codex" / "skills")
    args = parser.parse_args()

    source = args.input.resolve()
    out = args.output_dir.resolve()
    intermediate = out / "extracted"
    prepared = out / "ja"
    suffix = source.suffix.lower()

    if suffix in {".docx", ".docm"}:
        script = args.skills_root / "convert-docx-to-markdown-png" / "scripts" / "docx_to_markdown_png.py"
    elif suffix == ".pdf":
        script = args.skills_root / "convert-pdf-to-markdown-png" / "scripts" / "pdf_to_markdown_png.py"
    else:
        raise SystemExit(f"Unsupported source type: {source.suffix}")

    prep = args.skills_root / "translate-markdown-png-to-ja" / "scripts" / "prepare_markdown_png_translation.py"
    run([sys.executable, str(script), str(source), str(intermediate)])
    run([sys.executable, str(prep), str(intermediate / "document.md"), str(prepared)])
    print(f"Translate this file into Japanese: {prepared / 'document.ja.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
