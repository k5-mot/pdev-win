---
name: translate-document-to-ja-markdown-png
description: Convert English DOCX or PDF documents into Japanese Markdown plus PNG assets. Use when the user asks to translate .docx, .docm, or .pdf files into Japanese Markdown+PNG output; combine DOCX/PDF extraction skills with Markdown+PNG localization while preserving images and structure.
---

# Translate DOCX/PDF To Japanese Markdown+PNG

## Workflow

1. Determine the source type: DOCX uses `convert-docx-to-markdown-png`; PDF uses `convert-pdf-to-markdown-png`.
2. Review `proper_noun_glossary.csv` and add any document-specific proper noun mappings before extraction/translation.
3. Extract the document into an intermediate Markdown+PNG directory.
4. Use `translate-markdown-png-to-ja` to prepare and translate the extracted Markdown package, applying the glossary consistently.
5. Validate the Japanese Markdown and image links.
6. Return the final `document.ja.md`, image folders, and a short note about extraction warnings.

## Proper Noun Glossary

- Use `proper_noun_glossary.csv` as the source of truth for translating proper nouns, product names, organization names, feature names, and recurring named terms.
- The CSV columns are `english,japanese,notes`.
- Apply glossary entries consistently and case-sensitively when the source text clearly refers to the listed proper noun.
- Preserve the original English term when the Japanese column is blank, or when the term is inside code blocks, inline code, URLs, file paths, commands, identifiers, or frontmatter keys.
- When using the orchestration script, keep this glossary aligned with `translate-markdown-png-to-ja/proper_noun_glossary.csv` because the Markdown translation step uses that component skill.

## Orchestration Script

Use the helper when the three component scripts are available locally:

```bash
python scripts/document_to_ja_markdown_png.py input.docx output-dir --skills-root C:/Users/merry/.codex/skills
python scripts/document_to_ja_markdown_png.py input.pdf output-dir --skills-root C:/Users/merry/.codex/skills
```

The helper runs extraction and prepares the Japanese translation workspace. Codex still performs the actual English-to-Japanese translation in `document.ja.md`.

## Quality Rules

- Preserve all relative image links in the final Japanese Markdown.
- Keep source page or section boundaries when they help review.
- Report limitations such as scanned PDFs, missing extractable text, unsupported Word layouts, or images containing untranslated English.
- Do not overwrite unrelated files; write into a dedicated output directory.
