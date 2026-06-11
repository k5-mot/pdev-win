#!/usr/bin/env python3
"""Translate Markdown chunks to Japanese with OpenAI and assemble the result."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


SYSTEM_PROMPT = """You are a professional English-to-Japanese technical translator.
Translate English prose into natural Japanese while preserving Markdown exactly where practical.
Preserve headings, tables, lists, code fences, inline code, links, image references, URLs, commands,
file paths, identifiers, and product names. Translate every sentence and every paragraph.
Do not summarize, shorten, omit, or add commentary. Return only the translated Markdown."""


@dataclass(frozen=True)
class GlossaryEntry:
    english: str
    japanese: str
    notes: str = ""


def load_manifest(chunks_dir: Path) -> dict:
    manifest_path = chunks_dir / "chunks-manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"Manifest not found: {manifest_path}")
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def load_glossary(glossary_path: Optional[Path]) -> list[GlossaryEntry]:
    if glossary_path is None:
        return []

    resolved = glossary_path.expanduser().resolve()
    if not resolved.is_file():
        return []

    entries: list[GlossaryEntry] = []
    with resolved.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames and {"english", "japanese"}.issubset(set(reader.fieldnames)):
            for row in reader:
                english = (row.get("english") or "").strip()
                japanese = (row.get("japanese") or "").strip()
                notes = (row.get("notes") or "").strip()
                if english and japanese:
                    entries.append(GlossaryEntry(english=english, japanese=japanese, notes=notes))
            return entries

    with resolved.open("r", encoding="utf-8-sig", newline="") as fh:
        for row in csv.reader(fh):
            if len(row) >= 2 and row[0].strip() and row[1].strip():
                entries.append(
                    GlossaryEntry(
                        english=row[0].strip(),
                        japanese=row[1].strip(),
                        notes=row[2].strip() if len(row) >= 3 else "",
                    )
                )
    return entries


def relevant_glossary_entries(source: str, entries: list[GlossaryEntry]) -> list[GlossaryEntry]:
    source_lower = source.lower()
    return [entry for entry in entries if entry.english.lower() in source_lower]


def format_glossary(entries: list[GlossaryEntry]) -> str:
    if not entries:
        return ""

    lines = [
        "Use the following glossary with highest priority. If an English source term appears,",
        "render it exactly as the listed Japanese term instead of choosing a different translation.",
    ]
    for entry in entries:
        note = f" ({entry.notes})" if entry.notes else ""
        lines.append(f"- {entry.english} => {entry.japanese}{note}")
    return "\n".join(lines)


def glossary_pattern(term: str) -> re.Pattern[str]:
    escaped = re.escape(term)
    prefix = r"(?<![A-Za-z0-9])" if term[0].isalnum() else ""
    suffix = r"(?![A-Za-z0-9])" if term[-1].isalnum() else ""
    return re.compile(prefix + escaped + suffix, re.IGNORECASE)


def replace_unprotected_text(text: str, entries: list[GlossaryEntry]) -> str:
    if not entries:
        return text

    url_re = re.compile(r"https?://[^\s)>\]]+")
    inline_code_re = re.compile(r"`[^`\n]+`")
    patterns = [(glossary_pattern(entry.english), entry.japanese) for entry in entries]

    def replace_plain(segment: str) -> str:
        protected: list[str] = []

        def stash(match: re.Match[str]) -> str:
            protected.append(match.group(0))
            return f"\0{len(protected) - 1}\0"

        segment = url_re.sub(stash, segment)
        segment = inline_code_re.sub(stash, segment)
        for pattern, replacement in patterns:
            segment = pattern.sub(replacement, segment)
        for index, original in enumerate(protected):
            segment = segment.replace(f"\0{index}\0", original)
        return segment

    lines: list[str] = []
    in_fence = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            lines.append(line)
            continue
        lines.append(line if in_fence else replace_plain(line))
    return "".join(lines)


def translate_text(
    client,
    model: str,
    source: str,
    temperature: float,
    glossary_entries: list[GlossaryEntry],
) -> str:
    relevant_entries = relevant_glossary_entries(source, glossary_entries)
    glossary_prompt = format_glossary(relevant_entries)
    user_prompt = (
        "Translate the following Markdown completely into Japanese. "
        "Preserve the Markdown structure and translate all English prose.\n\n"
        f"{glossary_prompt}\n\n"
        f"Markdown to translate:\n\n{source}"
    )
    response = client.chat.completions.create(
        model=model,
        temperature=temperature,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )
    translated = response.choices[0].message.content.strip() + "\n"
    return replace_unprotected_text(translated, relevant_entries)


def default_glossary_path() -> Path:
    return Path(__file__).resolve().parents[1] / "assets" / "glossary.csv"


def load_env_file(env_file: Optional[Path]) -> None:
    try:
        from dotenv import load_dotenv
    except ImportError as exc:
        raise SystemExit(
            "python-dotenv is not installed. Run: python -m pip install -U docling openai python-dotenv"
        ) from exc

    skill_env = Path(__file__).resolve().parents[1] / ".env"
    cwd_env = Path.cwd() / ".env"
    for path in (skill_env, cwd_env):
        if path.is_file():
            load_dotenv(path, override=False)

    if env_file is not None:
        resolved = env_file.expanduser().resolve()
        if not resolved.is_file():
            raise SystemExit(f"Env file not found: {resolved}")
        load_dotenv(resolved, override=True)


def get_api_key() -> str:
    return os.environ.get("OPENAI_API_KEY") or "EMPTY"


def get_base_url() -> str | None:
    return os.environ.get("OPENAI_BASE_URL") or "http://localhost:4000"


def assemble_output(ja_dir: Path, output_path: Path, chunk_count: int) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    parts: list[str] = []
    for index in range(1, chunk_count + 1):
        path = ja_dir / f"chunk-{index:04d}.ja.md"
        if path.is_file():
            parts.append(path.read_text(encoding="utf-8").rstrip() + "\n")
    output_path.write_text("\n".join(parts), encoding="utf-8")


def translate_chunks(
    chunks_dir: Path,
    output_path: Path,
    model: str,
    base_url: str | None,
    api_key: str,
    glossary_entries: list[GlossaryEntry],
    temperature: float,
    force: bool,
    sleep_seconds: float,
) -> None:
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise SystemExit(
            "openai is not installed. Run: python -m pip install -U docling openai python-dotenv"
        ) from exc

    manifest = load_manifest(chunks_dir)
    chunks = manifest.get("chunks", [])
    ja_dir = chunks_dir / "ja"
    ja_dir.mkdir(parents=True, exist_ok=True)

    client_kwargs = {"api_key": api_key}
    if base_url:
        client_kwargs["base_url"] = base_url
    client = OpenAI(**client_kwargs)
    for item in chunks:
        index = int(item["index"])
        source_path = chunks_dir / str(item["path"])
        target_path = ja_dir / f"chunk-{index:04d}.ja.md"

        if target_path.is_file() and not force:
            assemble_output(ja_dir, output_path, len(chunks))
            continue

        source = source_path.read_text(encoding="utf-8")
        translated = translate_text(client, model, source, temperature, glossary_entries)
        target_path.write_text(translated, encoding="utf-8")
        assemble_output(ja_dir, output_path, len(chunks))
        print(f"translated chunk {index}/{len(chunks)}: {target_path}")

        if sleep_seconds > 0:
            time.sleep(sleep_seconds)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("chunks_dir", type=Path, help="Directory produced by chunk_text.py.")
    parser.add_argument("output_markdown", type=Path, help="Final Japanese Markdown path.")
    parser.add_argument("--env-file", type=Path, help="Optional .env path. Overrides default .env values.")
    parser.add_argument("--model", help="Model name. Defaults to OPENAI_MODEL, then gpt-4.1-mini.")
    parser.add_argument("--base-url", help="OpenAI-compatible API base URL. Defaults to OPENAI_BASE_URL.")
    parser.add_argument(
        "--glossary",
        type=Path,
        default=default_glossary_path(),
        help="CSV glossary path with english,japanese,notes columns. Defaults to assets/glossary.csv.",
    )
    parser.add_argument("--no-glossary", action="store_true", help="Disable glossary prompting and replacement.")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--force", action="store_true", help="Re-translate existing chunk files.")
    parser.add_argument("--sleep", type=float, default=0.0, help="Seconds to sleep between API calls.")
    args = parser.parse_args()

    load_env_file(args.env_file)
    model = args.model or os.environ.get("OPENAI_MODEL") or "gpt-4.1-mini"
    base_url = args.base_url or get_base_url()
    api_key = get_api_key()
    glossary_entries = [] if args.no_glossary else load_glossary(args.glossary)

    translate_chunks(
        args.chunks_dir.expanduser().resolve(),
        args.output_markdown.expanduser().resolve(),
        model,
        base_url,
        api_key,
        glossary_entries,
        args.temperature,
        args.force,
        args.sleep,
    )
    print(args.output_markdown.expanduser().resolve())
    return 0


if __name__ == "__main__":
    sys.exit(main())
