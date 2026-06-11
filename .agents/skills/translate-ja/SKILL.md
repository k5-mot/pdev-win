---
name: translate-ja
description: Sequentially translate English PDF documents into Japanese Markdown. Use when Codex needs to install docling/openai, extract an English PDF into Markdown with linked image assets using Docling, chunk English Markdown into sentence-complete chunks of 500 words or fewer, translate each chunk with the OpenAI Python package, and append translated chunks into a final Japanese Markdown file.
---

# Translate English PDF To Japanese Markdown

## Workflow

1. Install runtime dependencies in the active Python environment:

```bash
python -m pip install -U docling openai python-dotenv
```

2. Configure OpenAI-compatible API settings in `.env`. `translate_ja.py` reads `.env` from the skill directory, then from the current working directory. An explicit `--env-file` path overrides both.

```bash
OPENAI_BASE_URL=http://localhost:40000
OPENAI_API_KEY=sk-litellm-master-key
OPENAI_MODEL=gemma4:31b
```

3. Convert the source English PDF into Markdown plus image assets:

```bash
python /path/to/translate-ja/scripts/convert_to_md.py /path/to/source.pdf /path/to/workdir
```

This writes `workdir/document.md` and Docling image artifacts next to it when Docling can export referenced images.

4. Chunk the Markdown into English sentence-complete chunks of 500 words or fewer:

```bash
python /path/to/translate-ja/scripts/chunk_text.py /path/to/workdir/document.md /path/to/workdir/chunks --max-words 500
```

Chunking joins consecutive English sentences until adding another sentence would exceed `--max-words`. For example, 300 words + 150 words + 100 words becomes one 450-word chunk followed by one 100-word chunk. A single sentence over the limit is emitted as its own chunk.

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
- `scripts/chunk_text.py`: Split Markdown into sentence-complete chunks capped by word count.
- `scripts/translate_ja.py`: Translate each chunk with OpenAI and assemble Japanese Markdown incrementally.
