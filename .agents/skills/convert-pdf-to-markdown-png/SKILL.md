---
name: convert-pdf-to-markdown-png
description: Convert PDF files into Markdown plus PNG assets using pypdf and Pillow. Use when the user asks to extract, convert, or package .pdf content as Markdown with embedded PDF images or page text snapshot PNGs, especially for English or mixed-language document extraction workflows.
---

# Convert PDF To Markdown+PNG

## Workflow

1. Confirm the input is a `.pdf` and choose an output directory.
2. Run `scripts/pdf_to_markdown_png.py <input.pdf> <output-dir>`.
3. Inspect `output-dir/document.md`, `output-dir/images/*.png`, and `output-dir/manifest.json`.
4. Explain any warnings, especially when a PDF contains scanned pages or vector-only page art.

## Script

Use the bundled converter first:

```bash
python scripts/pdf_to_markdown_png.py input.pdf output-dir
```

The script uses `pypdf` for PDF text and embedded image extraction, and `Pillow` to normalize image assets to PNG. Because `pypdf` and `Pillow` alone do not faithfully rasterize arbitrary PDF pages, page PNGs are text snapshots unless a page contains extractable embedded images.

It emits:

- `document.md`
- `images/pdf-image-0001.png`, etc.
- `pages/page-0001.png`, etc. text snapshot PNGs
- `manifest.json` with page counts, assets, and warnings

## Quality Rules

- Preserve page boundaries with `## Page N` headings.
- Link extracted images near the page where they were found.
- For scanned PDFs with little or no extractable text, report the limitation and suggest OCR as a follow-up.
- Do not claim visual fidelity for `pypdf`/`Pillow` page snapshots.

## Dependencies

Install missing packages only when needed:

```bash
python -m pip install pypdf Pillow
```
