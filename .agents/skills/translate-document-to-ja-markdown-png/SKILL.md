---
name: translate-document-to-ja-markdown-png
description: Convert English DOCX or PDF documents into Japanese Markdown plus PNG assets. Use when translating .docx, .docm, or .pdf files into Japanese Markdown+PNG output, including workflows that prefer docling-mcp or a configured Docling API for extraction, fall back to local Python extraction when needed, split long English text for local LLMs around 30B parameters with 32k context windows, preserve images and Markdown structure, and run post-translation quality checks for terminology and Japanese style consistency.
---

# Translate DOCX/PDF To Japanese Markdown+PNG

## Completion Contract

- Do not treat extraction, workspace preparation, or chunk creation as translation completion.
- Do not return `document.ja.md` as final if it is still an English copy of `document.md`.
- Do not return chunk placeholders in `chunks/ja/*.ja.md` as final translated chunks.
- A task is complete only after the English prose in `document.ja.md` or every `chunks/ja/*.ja.md` file has been translated into Japanese, the translated chunks have been assembled when chunking is used, and the quality checks pass or their remaining warnings are explicitly reported.
- If no translation engine is available, stop after preparation and clearly say that translation is not complete; do not imply that the Japanese Markdown has been translated.

## Workflow

1. Determine the source type: DOCX uses `convert-docx-to-markdown-png`; PDF uses `convert-pdf-to-markdown-png`.
2. Review `proper_noun_glossary.csv` and add any document-specific proper noun mappings before extraction/translation.
3. Extract the document into an intermediate Markdown+PNG directory. Follow the selected conversion skill's backend order: `docling-mcp`, Docling API settings from `.codex/config.toml`, local `docling` Python package, then the bundled lightweight fallback script.
4. Use `translate-markdown-png-to-ja` to prepare the extracted Markdown package. This creates a translation workspace only; it does not complete translation.
5. If the English Markdown is too long for the target model, split it with `scripts/chunk_markdown_for_translation.py`.
6. Translate each chunk into Japanese, replacing the English placeholder text in `chunks/ja/*.ja.md`. If not chunking, translate `ja/document.ja.md` directly.
7. Assemble translated chunks back into `ja/document.ja.md` in manifest order when chunking is used.
8. Validate the Japanese Markdown, image links, terminology, and Japanese style consistency.
9. Return the final translated `document.ja.md`, image folders, chunk directory when used, and a short note about extraction or review warnings.

## Extraction Backend Decision

Always tell the user which extraction backend was selected and why:

- Use `docling-mcp` when the MCP tools are available in the current Codex session and conversion succeeds.
- If MCP exists but fails, report the MCP failure reason and try the Docling API.
- For the Docling API, read `DOCLING_SERVICE_URL` and `DOCLING_SERVICE_API_KEY` from `.codex/config.toml` under `[mcp_servers.docling.env]`, then call the Docling Serve conversion API.
- If the API is unavailable or unauthorized, try the local `docling` Python package when installed.
- If none of the Docling paths work, use the component skill's bundled Python extraction script and mark this fallback in the extraction manifest or final report.

Do not treat a successful extraction backend check as translation completion.

## Local LLM Chunking

- Assume local LLMs around 30B parameters and 32k context windows need conservative chunk sizes.
- Prefer `--max-chars 20000` to leave room for instructions, glossary context, source text, and Japanese output. Lower it for dense tables or complex technical content.
- Split on Markdown page headings, section headings, blank-line paragraphs, tables, and fenced code boundaries. Do not split inside fenced code blocks, Markdown tables, image links, or tightly connected numbered/bulleted procedures.
- Preserve page headings such as `## Page N` so reviewers can trace each translation back to the source.
- Carry a short continuity note between chunks when needed: document title, current section, unresolved abbreviations, and important terminology choices.
- After chunk translation, concatenate translated chunks in numeric order and keep all image paths unchanged.
- Before assembly, compare `chunks/en/*.md` and `chunks/ja/*.ja.md`. If a Japanese chunk is identical or mostly English prose, translate it before continuing.

## Proper Noun Glossary

- Use `proper_noun_glossary.csv` as the source of truth for translating proper nouns, product names, organization names, feature names, and recurring named terms.
- The CSV columns are `english,japanese,notes`.
- Apply glossary entries consistently and case-sensitively when the source text clearly refers to the listed proper noun.
- Preserve the original English term when the Japanese column is blank, or when the term is inside code blocks, inline code, URLs, file paths, commands, identifiers, or frontmatter keys.
- When using the orchestration script, keep this glossary aligned with `translate-markdown-png-to-ja/proper_noun_glossary.csv` because the Markdown translation step uses that component skill.

## Orchestration Script

Use the helper when the three component scripts are available locally:

```bash
python /path/to/skills/translate-document-to-ja-markdown-png/scripts/document_to_ja_markdown_png.py /path/to/input.docx /path/to/output-dir --skills-root /path/to/skills
python /path/to/skills/translate-document-to-ja-markdown-png/scripts/document_to_ja_markdown_png.py /path/to/input.pdf /path/to/output-dir --skills-root /path/to/skills
python /path/to/skills/translate-document-to-ja-markdown-png/scripts/document_to_ja_markdown_png.py /path/to/input.pdf /path/to/output-dir --skills-root /path/to/skills --chunk --max-chars 20000
```

The helper runs extraction and prepares the Japanese translation workspace. The translation engine can be any suitable system: a local LLM, hosted model, human translator, or another translation workflow.

Important: the helper does not translate prose. Its output is a prepared workspace containing English placeholder content that must still be translated.

## Chunking Script

Use this helper after extraction when the source Markdown is long:

```bash
python /path/to/skills/translate-document-to-ja-markdown-png/scripts/chunk_markdown_for_translation.py /path/to/output-dir/extracted/document.md /path/to/output-dir/chunks --max-chars 20000
```

It emits:

- `chunks/en/chunk-0001.md`, etc.
- `chunks/ja/chunk-0001.ja.md`, etc. as placeholders for translated chunks
- `chunks/chunks-manifest.json` with chunk order and source character counts

Translate each `chunks/en/*.md` file into its matching `chunks/ja/*.ja.md`, replacing the English placeholder content. Then concatenate the Japanese chunks in manifest order into `/path/to/output-dir/ja/document.ja.md`.

Never skip this translation step. The initial `chunks/ja/*.ja.md` files are placeholders copied from the English source so that paths and structure are available during translation.

## Quality Check

After translation, run both structure validation and the quality checker:

```bash
python /path/to/skills/translate-markdown-png-to-ja/scripts/prepare_markdown_png_translation.py --check /path/to/output-dir/ja/document.ja.md
python /path/to/skills/translate-document-to-ja-markdown-png/scripts/check_translation_quality.py /path/to/output-dir/extracted/document.md /path/to/output-dir/ja/document.ja.md --glossary /path/to/skills/translate-document-to-ja-markdown-png/proper_noun_glossary.csv
```

Review warnings for:

- glossary terms whose required Japanese rendering is missing
- inconsistent polite/plain Japanese style (`desu/masu` style mixed with dominant plain-form endings)
- leftover English prose outside code, URLs, paths, identifiers, and image links
- missing or changed image references
- large source/translation length mismatches that may indicate skipped content

If `possible_untranslated_english` warnings remain, inspect them. Do not declare the translation complete when the warnings point to untranslated prose. Proper nouns, acronyms, operation names, URLs, code, paths, and image labels may remain in English when appropriate.

## Quality Rules

- Preserve all relative image links in the final Japanese Markdown.
- Keep source page or section boundaries when they help review.
- Use the glossary for proper nouns and recurring technical terms.
- Keep either polite style or plain style consistent; for technical documents, prefer a clear plain style unless the source or user requests polite style.
- Run a final terminology pass for product names, organization names, feature names, acronyms, units, and domain-specific terms.
- Run a final untranslated-prose pass. Search for long English sentences and compare against the source if needed.
- Report limitations such as scanned PDFs, missing extractable text, unsupported Word layouts, or images containing untranslated English.
- Do not overwrite unrelated files; write into a dedicated output directory.
