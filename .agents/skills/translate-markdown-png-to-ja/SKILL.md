---
name: translate-markdown-png-to-ja
description: Translate English Markdown plus PNG asset folders into Japanese while preserving Markdown structure, image references, tables, code blocks, links, and filenames. Use when the user asks to localize Markdown+PNG outputs, extracted document packages, or English technical documents into Japanese.
---

# Translate Markdown+PNG To Japanese

## Workflow

1. Identify the English Markdown file and its related PNG/image directory.
2. Review `proper_noun_glossary.csv` and add any document-specific proper noun mappings before translating.
3. Run `scripts/prepare_markdown_png_translation.py <input.md> <output-dir>` to copy PNG assets, copy the glossary, and create a translation workspace.
4. Translate `output-dir/document.ja.md` into natural Japanese while preserving Markdown syntax, code blocks, links, table structure, anchors, and image paths.
5. Re-run the script with `--check output-dir/document.ja.md` to validate image references and basic Markdown hazards.

## Proper Noun Glossary

- Use `proper_noun_glossary.csv` as the source of truth for translating proper nouns, product names, organization names, feature names, and recurring named terms.
- The CSV columns are `english,japanese,notes`.
- Apply glossary entries consistently and case-sensitively when the source text clearly refers to the listed proper noun.
- Preserve the original English term when the Japanese column is blank, or when the term is inside code blocks, inline code, URLs, file paths, commands, identifiers, or frontmatter keys.
- Add document-specific entries before translation when the source uses names that need consistent Japanese rendering.

## Translation Rules

- Translate prose, headings, captions, alt text, and table text into Japanese.
- Preserve code blocks, inline code, URLs, file paths, commands, identifiers, and frontmatter keys unless the user asks otherwise.
- Preserve image filenames and relative paths.
- Keep Markdown table column counts stable.
- Prefer readable Japanese over literal word-for-word translation.
- If a PNG contains English text that must be translated, note that image editing/OCR is needed unless the user provided editable source.

## Script

```bash
python scripts/prepare_markdown_png_translation.py input.md output-dir
python scripts/prepare_markdown_png_translation.py --check output-dir/document.ja.md
```

The script prepares asset copies and checks common structural issues; Codex performs the actual translation.
