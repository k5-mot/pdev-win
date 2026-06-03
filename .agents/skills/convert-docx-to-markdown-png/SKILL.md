---
name: convert-docx-to-markdown-png
description: Convert DOCX documents into Markdown plus PNG image assets using python-docx and Pillow. Use when the user asks to extract, convert, or preserve content from .docx/.docm Word files as Markdown with images, tables, headings, and document media saved as PNG files.
---

# Convert DOCX To Markdown+PNG

## Workflow

1. Confirm the input is a `.docx` or compatible Word file and choose an output directory.
2. Run `scripts/docx_to_markdown_png.py <input.docx> <output-dir>`.
3. Inspect `output-dir/document.md` and `output-dir/images/*.png`.
4. If document ordering or formatting matters, spot-check headings, tables, lists, and image placement against the original DOCX.

## Script

Use the bundled converter first:

```bash
python scripts/docx_to_markdown_png.py input.docx output-dir
```

The script uses `python-docx` for document structure and media access, and `Pillow` to normalize extracted images to PNG. It emits:

- `document.md`
- `images/image-0001.png`, etc.
- `manifest.json` with source path, counts, and warnings

## Quality Rules

- Preserve Markdown image links relative to `document.md`.
- Convert Word heading styles (`Heading 1` through `Heading 6`) into Markdown headings.
- Convert tables into pipe tables when possible.
- Keep unsupported or ambiguous layout features as warnings in `manifest.json` rather than silently pretending they were preserved.
- Do not overwrite unrelated user files; write into the chosen output directory.

## Dependencies

Install missing packages only when needed:

```bash
python -m pip install python-docx Pillow
```
