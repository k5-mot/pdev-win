---
name: translate-ja
description: Sequentially translate English PDF documents into Japanese Markdown. Use when Codex needs to install docling/openai, extract an English PDF into Markdown with linked image assets using Docling, chunk English Markdown into sentence-complete chunks of 500 words or fewer, translate each chunk with the OpenAI Python package, and append translated chunks into a final Japanese Markdown file.
---

# Translate English PDF To Japanese Markdown

## Workflow

1. Install runtime dependencies in the active Python environment:

```bash
python -m pip install -U docling openai python-dotenv requests
```

2. Configure OpenAI-compatible API settings in `.env`. `translate_ja.py` and `convert_to_md_remote.py` read `.env` from the skill directory, then from the current working directory. An explicit `--env-file` path overrides both.

```bash
OPENAI_BASE_URL=http://localhost:40000
OPENAI_API_KEY=sk-litellm-master-key
OPENAI_MODEL=gemma4:31b
DOCLING_SERVE_BASE_URL=http://localhost:50000
DOCLING_SERVE_API_KEY=sk-docling-serve-api-key
```

3. Convert the source English PDF into Markdown plus image assets. Prefer docling-serve when `DOCLING_SERVE_BASE_URL` is configured and the container is ready:

```bash
python /path/to/translate-ja/scripts/convert_to_md_remote.py /path/to/source.pdf /path/to/workdir
```

`convert_to_md_remote.py` submits a job to `POST /v1/convert/file/async` with `target_type=zip`, `to_formats=md`, `image_export_mode=referenced`, and `include_images=true`, polls `/v1/status/poll/{task_id}`, then fetches `/v1/result/{task_id}`. It writes `workdir/document.md` and extracts referenced PNG/JPEG image assets from the zip response.

The remote converter uses the full analysis profile by default: `dlparse_v4`, OCR, accurate table structure, layout preset, picture classification, picture description, code/formula enrichment, and chart extraction. It defaults to `ocr_preset=tesseract`, `table_structure_preset=tableformerv2`, and `picture_description_preset=granite_vision`; override them with `--ocr-preset`, `--table-structure-preset`, or `--picture-description-preset` if the server exposes different presets.

If docling-serve is unavailable, fall back to local Docling:

```bash
python /path/to/translate-ja/scripts/convert_to_md.py /path/to/source.pdf /path/to/workdir
```

This writes `workdir/document.md` and Docling image artifacts next to it when Docling can export referenced images.

4. Chunk the Markdown. Prefer docling-serve when `DOCLING_SERVE_BASE_URL` is configured and `/ready` succeeds:

```bash
python /path/to/translate-ja/scripts/chunk_text_remote.py /path/to/workdir/document.md /path/to/workdir/chunks --max-words 500
```

`chunk_text_remote.py` submits the file to `POST /v1/chunk/{path_name}/file/async` using the `hierarchical` chunker by default, polls `/v1/status/poll/{task_id}`, fetches `/v1/result/{task_id}`, and writes the same `chunks/en/chunk-0001.md` plus `chunks-manifest.json` layout used by `translate_ja.py`. Use `--chunker hybrid` to switch to the hybrid chunker when the server supports it for the input format. It records `--max-words` for compatibility and passes the value as `chunking_max_tokens` unless `--max-tokens` is provided.

If docling-serve is unavailable, fall back to local sentence-complete Markdown chunking:

```bash
python /path/to/translate-ja/scripts/chunk_text.py /path/to/workdir/document.md /path/to/workdir/chunks --max-words 500
```

Local chunking joins consecutive English sentences until adding another sentence would exceed `--max-words`. For example, 300 words + 150 words + 100 words becomes one 450-word chunk followed by one 100-word chunk. A single sentence over the limit is emitted as its own chunk.

5. Translate chunks sequentially with OpenAI and append results into Japanese Markdown:

```bash
python /path/to/translate-ja/scripts/translate_ja.py /path/to/workdir/chunks /path/to/workdir/document.ja.md
```

The script translates one chunk at a time, saves `chunks/ja/chunk-0001.ja.md` style intermediate files, and rebuilds the final output in manifest order after each successful chunk. Re-run the same command to resume; existing translated chunk files are reused unless `--force` is passed.

By default, `translate_ja.py` reads `assets/glossary.csv` and applies its `english,japanese,notes` entries with priority. Relevant glossary entries are included in the LLM prompt, and remaining exact English terms in the translated output are replaced with the glossary Japanese outside fenced code blocks, inline code, and URLs. Use `--glossary /path/to/glossary.csv` to choose another glossary, or `--no-glossary` to disable this behavior.

## Translation Rules

- Preserve Markdown structure, headings, tables, lists, code fences, inline code, links, and image references.
- Translate English prose into natural Japanese.
- Apply `assets/glossary.csv` terms before accepting the LLM's default terminology.
- Keep product names, identifiers, commands, file paths, URLs, and code in English unless a Japanese rendering is clearly standard.
- Use a consistent Japanese technical-document style.
- Do not claim completion if API credentials are missing, API calls fail, or untranslated English prose remains in the final Markdown.

## Scripts

- `scripts/convert_to_md.py`: Convert a PDF to `document.md` with Docling.
- `scripts/convert_to_md_remote.py`: Convert a PDF to `document.md` plus referenced image assets using docling-serve `POST /v1/convert/file/async`.
- `scripts/chunk_text_remote.py`: Split a document with docling-serve `POST /v1/chunk/{path_name}/file/async` and write the standard chunk manifest.
- `scripts/chunk_text.py`: Split Markdown into sentence-complete chunks capped by word count.
- `scripts/translate_ja.py`: Translate each chunk with OpenAI and assemble Japanese Markdown incrementally.
