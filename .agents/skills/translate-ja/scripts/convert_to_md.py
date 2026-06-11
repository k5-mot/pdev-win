#!/usr/bin/env python3
"""Convert an English PDF to Markdown plus Docling image artifacts."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def convert_pdf(pdf_path: Path, output_dir: Path, output_name: str) -> Path:
    try:
        from docling.document_converter import DocumentConverter
    except ImportError as exc:
        raise SystemExit(
            "docling is not installed. Run: python -m pip install -U docling openai"
        ) from exc

    try:
        from docling_core.types.doc import ImageRefMode
    except ImportError:
        ImageRefMode = None

    output_dir.mkdir(parents=True, exist_ok=True)
    md_path = output_dir / output_name

    converter = DocumentConverter()
    result = converter.convert(str(pdf_path))
    document = result.document

    if ImageRefMode is not None and hasattr(document, "save_as_markdown"):
        try:
            document.save_as_markdown(md_path, image_mode=ImageRefMode.REFERENCED)
            return md_path
        except TypeError:
            pass

    markdown = None
    if hasattr(document, "export_to_markdown"):
        if ImageRefMode is not None:
            try:
                markdown = document.export_to_markdown(image_mode=ImageRefMode.REFERENCED)
            except TypeError:
                markdown = None
        if markdown is None:
            markdown = document.export_to_markdown()

    if markdown is None:
        raise SystemExit("Docling conversion succeeded, but Markdown export is unavailable.")

    md_path.write_text(markdown, encoding="utf-8")
    return md_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Input English PDF path.")
    parser.add_argument("output_dir", type=Path, help="Directory for Markdown and image assets.")
    parser.add_argument("--output-name", default="document.md", help="Markdown filename.")
    args = parser.parse_args()

    pdf_path = args.pdf.expanduser().resolve()
    if not pdf_path.is_file():
        parser.error(f"PDF not found: {pdf_path}")

    md_path = convert_pdf(pdf_path, args.output_dir.expanduser().resolve(), args.output_name)
    print(md_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
