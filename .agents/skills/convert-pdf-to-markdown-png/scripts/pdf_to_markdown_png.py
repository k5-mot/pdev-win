#!/usr/bin/env python3
"""Convert a PDF file to Markdown, extracted PNG assets, and text snapshot PNGs."""

from __future__ import annotations

import argparse
import io
import json
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader


def save_image(image_file, images_dir: Path, index: int) -> str:
    images_dir.mkdir(parents=True, exist_ok=True)
    out = images_dir / f"pdf-image-{index:04d}.png"
    data = image_file.data
    with Image.open(io.BytesIO(data)) as image:
        if image.mode not in ("RGB", "RGBA"):
            image = image.convert("RGBA")
        image.save(out, "PNG")
    return f"images/{out.name}"


def page_snapshot(text: str, pages_dir: Path, page_number: int) -> str:
    pages_dir.mkdir(parents=True, exist_ok=True)
    out = pages_dir / f"page-{page_number:04d}.png"
    image = Image.new("RGB", (1240, 1754), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    y = 40
    draw.text((40, y), f"Page {page_number} text snapshot", fill="black", font=font)
    y += 32
    for line in textwrap.wrap(text or "[No extractable text]", width=120)[:70]:
        draw.text((40, y), line, fill="black", font=font)
        y += 22
    image.save(out, "PNG")
    return f"pages/{out.name}"


def convert(input_path: Path, output_dir: Path) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    images_dir = output_dir / "images"
    pages_dir = output_dir / "pages"
    reader = PdfReader(str(input_path))
    markdown = [f"# {input_path.stem}"]
    warnings = ["pypdf/Pillow text snapshots are not faithful page rasterizations."]
    image_count = 0

    for idx, page in enumerate(reader.pages, start=1):
        text = (page.extract_text() or "").strip()
        snapshot = page_snapshot(text, pages_dir, idx)
        markdown.append(f"## Page {idx}\n\n![page {idx}]({snapshot})")
        if text:
            markdown.append(text)
        else:
            markdown.append("[No extractable text found on this page.]")
            warnings.append(f"Page {idx} has no extractable text; OCR may be required.")

        for image_file in getattr(page, "images", []):
            try:
                image_count += 1
                rel = save_image(image_file, images_dir, image_count)
                markdown.append(f"![embedded image {image_count}]({rel})")
            except Exception as exc:
                warnings.append(f"Could not export image on page {idx}: {exc}")

    md_path = output_dir / "document.md"
    md_path.write_text("\n\n".join(markdown) + "\n", encoding="utf-8")
    manifest = {
        "source": str(input_path),
        "markdown": str(md_path),
        "page_count": len(reader.pages),
        "embedded_image_count": image_count,
        "warnings": warnings,
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    manifest = convert(args.input, args.output_dir)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
