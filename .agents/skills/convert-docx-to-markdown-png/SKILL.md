---
name: convert-docx-to-markdown-png
description: Convert DOCX documents into Markdown plus PNG image assets. Prefer docling-mcp when available, otherwise use a configured Docling API, the docling Python package, or the bundled python-docx/Pillow fallback. Use when the user asks to extract, convert, or preserve content from .docx/.docm Word files as Markdown with images, tables, headings, and document media saved as PNG files.
---

# Convert DOCX To Markdown+PNG

## Workflow

1. Confirm the input is a `.docx` or compatible Word file and choose an output directory.
2. Choose and tell the user the extraction backend in this order:
   - `docling-mcp`, when the MCP tools are available in the current Codex session and conversion succeeds.
   - Docling Serve API, when `.codex/config.toml` contains `[mcp_servers.docling.env]` with a usable `DOCLING_SERVICE_URL` and `DOCLING_SERVICE_API_KEY`.
   - The local `docling` Python package, when it is installed and usable.
   - The bundled `scripts/docx_to_markdown_png.py` fallback.
3. Extract the DOCX into `output-dir/document.md` plus any PNG assets.
4. Inspect `output-dir/document.md`, `output-dir/images/*.png` if present, and `output-dir/manifest.json`.
5. If document ordering or formatting matters, spot-check headings, tables, lists, and image placement against the original DOCX.

## Docling MCP

When `mcp__docling` tools are available, use them before local scripts:

1. Call `convert_document_into_docling_document` with the absolute DOCX path.
2. Call `export_docling_document_to_markdown` with the returned `document_key`.
3. Write the returned Markdown to `output-dir/document.md`.
4. If the MCP result does not expose referenced image files, note that limitation in `manifest.json` and use the bundled converter only to supplement PNG image extraction when images are required.

If MCP conversion fails because the remote service is unavailable, authentication fails, or local fallback is missing, report that reason and continue to the next backend.

## Docling API

When MCP is unavailable or cannot convert, read API settings from `.codex/config.toml`:

- `DOCLING_SERVICE_URL`
- `DOCLING_SERVICE_API_KEY`

Use `POST {DOCLING_SERVICE_URL}/v1/convert/file` with multipart form data:

- `files`: the DOCX file
- `to_formats`: `md,json`
- `image_export_mode`: `embedded`
- `include_images`: `true`

Send `DOCLING_SERVICE_API_KEY` as the `X-Api-Key` header unless the local deployment documents a different auth header. Save `document.md_content` as `output-dir/document.md`. When `document.json_content.pictures[*].image.uri` or Markdown image references contain `data:image/png;base64,...`, decode them to `output-dir/images/*.png` and rewrite Markdown image links to relative paths. Write `manifest.json` with the backend, source, warnings, and conversion status.

## Script

Use the bundled converter only after the Docling options above are unavailable or fail:

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
