#!/usr/bin/env python3
"""MarkdownチャンクをOpenAI互換APIで日本語へ翻訳し、最終Markdownを組み立てる。"""

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


SYSTEM_PROMPT = """あなたは英日翻訳を専門とする技術翻訳者です。
英語本文を自然な日本語へ翻訳し、可能な限りMarkdown構造をそのまま保ってください。
見出し、表、リスト、コードフェンス、インラインコード、リンク、画像参照、URL、コマンド、
ファイルパス、識別子、製品名は壊さず保持してください。すべての文と段落を翻訳してください。
要約、短縮、省略、解説の追加はしないでください。翻訳後のMarkdownだけを返してください。"""


@dataclass(frozen=True)
class GlossaryEntry:
    english: str
    japanese: str
    notes: str = ""


def load_manifest(chunks_dir: Path) -> dict:
    """チャンク一覧と順序を記録したマニフェストを読み込む。"""
    manifest_path = chunks_dir / "chunks-manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"Manifest not found: {manifest_path}")
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def load_glossary(glossary_path: Optional[Path]) -> list[GlossaryEntry]:
    """CSV用語集を読み込み、英語-日本語の対応リストへ変換する。"""
    if glossary_path is None:
        return []

    resolved = glossary_path.expanduser().resolve()
    if not resolved.is_file():
        return []

    entries: list[GlossaryEntry] = []
    with resolved.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        # ヘッダー付きCSVを優先し、notes列があればプロンプト補足として使う。
        if reader.fieldnames and {"english", "japanese"}.issubset(set(reader.fieldnames)):
            for row in reader:
                english = (row.get("english") or "").strip()
                japanese = (row.get("japanese") or "").strip()
                notes = (row.get("notes") or "").strip()
                if english and japanese:
                    entries.append(GlossaryEntry(english=english, japanese=japanese, notes=notes))
            return entries

    # ヘッダーなしCSVも扱えるようにして、既存の簡易用語集をそのまま使えるようにする。
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
    """翻訳対象に登場する用語集エントリだけを抽出する。"""
    source_lower = source.lower()
    return [entry for entry in entries if entry.english.lower() in source_lower]


def format_glossary(entries: list[GlossaryEntry]) -> str:
    """LLMプロンプトへ挿入する用語集テキストを作る。"""
    if not entries:
        return ""

    lines = [
        "次の用語集を最優先で適用してください。英語原文に用語が出てきた場合は、",
        "別の訳語を選ばず、対応する日本語表記を正確に使ってください。",
    ]
    for entry in entries:
        note = f" ({entry.notes})" if entry.notes else ""
        lines.append(f"- {entry.english} => {entry.japanese}{note}")
    return "\n".join(lines)


def glossary_pattern(term: str) -> re.Pattern[str]:
    """英数字語の途中に誤って一致しない用語置換パターンを作る。"""
    escaped = re.escape(term)
    prefix = r"(?<![A-Za-z0-9])" if term[0].isalnum() else ""
    suffix = r"(?![A-Za-z0-9])" if term[-1].isalnum() else ""
    return re.compile(prefix + escaped + suffix, re.IGNORECASE)


def replace_unprotected_text(text: str, entries: list[GlossaryEntry]) -> str:
    """コード、URL、インラインコードを避けて用語集の表記を適用する。"""
    if not entries:
        return text

    url_re = re.compile(r"https?://[^\s)>\]]+")
    inline_code_re = re.compile(r"`[^`\n]+`")
    patterns = [(glossary_pattern(entry.english), entry.japanese) for entry in entries]

    def replace_plain(segment: str) -> str:
        """保護対象を退避してから、通常テキスト部分だけを置換する。"""
        protected: list[str] = []

        def stash(match: re.Match[str]) -> str:
            """置換してはいけない断片を一時トークンに差し替える。"""
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
        # コードフェンス内はコマンドや識別子を壊しやすいため、用語置換を行わない。
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
    """1チャンク分のMarkdownを日本語へ翻訳し、用語集表記を整える。"""
    relevant_entries = relevant_glossary_entries(source, glossary_entries)
    glossary_prompt = format_glossary(relevant_entries)
    user_prompt = (
        "次のMarkdownを日本語へ完全に翻訳してください。"
        "Markdown構造を保ち、英語本文はすべて翻訳してください。\n\n"
        f"{glossary_prompt}\n\n"
        f"翻訳対象Markdown:\n\n{source}"
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
    """スキル同梱の既定用語集パスを返す。"""
    return Path(__file__).resolve().parents[1] / "assets" / "glossary.csv"


def load_env_file(env_file: Optional[Path]) -> None:
    """スキル配下、カレントディレクトリ、明示指定の順に.envを読み込む。"""
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
    """OpenAI互換APIキーを取得し、未設定時はローカルAPI向けのダミー値を返す。"""
    return os.environ.get("OPENAI_API_KEY") or "EMPTY"


def get_base_url() -> str | None:
    """OpenAI互換APIのベースURLを取得する。"""
    return os.environ.get("OPENAI_BASE_URL") or "http://localhost:4000"


def assemble_output(ja_dir: Path, output_path: Path, chunk_count: int) -> None:
    """翻訳済みチャンクを番号順に結合して最終Markdownを書き直す。"""
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
    """未翻訳チャンクを順番に翻訳し、途中結果を保存しながら最終出力を更新する。"""
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
            # 再実行時は既存チャンクを再利用し、途中停止した続きから進める。
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
    """コマンドライン引数を読み取り、チャンク翻訳を実行する。"""
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
