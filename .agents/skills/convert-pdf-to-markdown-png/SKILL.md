---
name: convert-pdf-to-markdown-png
description: Convert PDF files into Markdown plus PNG assets. Prefer docling-mcp when available, otherwise use a configured Docling API, the docling Python package, or the bundled pypdf/Pillow fallback. Use when the user asks to extract, convert, or package .pdf content as Markdown with embedded PDF images or page text snapshot PNGs, especially for English or mixed-language document extraction workflows.
---

# Convert PDF To Markdown+PNG

## Workflow

1. Confirm the input is a `.pdf` and choose an output directory.
2. Choose and tell the user the extraction backend in this order:
   - `docling-mcp`, when the MCP tools are available in the current Codex session and conversion succeeds.
   - Docling Serve API, when `.codex/config.toml` contains `[mcp_servers.docling.env]` with a usable `DOCLING_SERVICE_URL` and `DOCLING_SERVICE_API_KEY`.
   - The local `docling` Python package, when it is installed and usable.
   - The bundled `scripts/pdf_to_markdown_png.py` fallback.
3. Extract the PDF into `output-dir/document.md` plus any PNG assets.
4. Inspect `output-dir/document.md`, `output-dir/images/*.png`, `output-dir/pages/*.png` if present, and `output-dir/manifest.json`.
5. Explain any warnings, especially when a PDF contains scanned pages or vector-only page art.

## Docling MCP

When `mcp__docling` tools are available, use them before local scripts:

1. Call `convert_document_into_docling_document` with the absolute PDF path.
2. Call `export_docling_document_to_markdown` with the returned `document_key`.
3. Write the returned Markdown to `output-dir/document.md`.
4. If the MCP result does not expose referenced image/page files, note that limitation in `manifest.json` and use the bundled converter only to supplement PNG extraction when page or embedded image PNGs are required.

If MCP conversion fails because the remote service is unavailable, authentication fails, or local fallback is missing, report that reason and continue to the next backend.

## Docling API

When MCP is unavailable or cannot convert, read API settings from `.codex/config.toml`:

- `DOCLING_SERVICE_URL`
- `DOCLING_SERVICE_API_KEY`

Use `POST {DOCLING_SERVICE_URL}/v1/convert/file` with multipart form data:

- `files`: the PDF file
- `to_formats`: `md,json`
- `image_export_mode`: `embedded`
- `include_images`: `true`
- `do_ocr`: `true` unless the user asks to skip OCR

Send `DOCLING_SERVICE_API_KEY` as the `X-Api-Key` header unless the local deployment documents a different auth header. Save `document.md_content` as `output-dir/document.md`. When `document.json_content.pictures[*].image.uri` or Markdown image references contain `data:image/png;base64,...`, decode them to `output-dir/images/*.png` or `output-dir/pages/*.png` and rewrite Markdown image links to relative paths. Write `manifest.json` with the backend, source, warnings, page/image counts when known, and conversion status.

## Script

Use the bundled converter only after the Docling options above are unavailable or fail:

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
