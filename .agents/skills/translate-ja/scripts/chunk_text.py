#!/usr/bin/env python3
"""Markdownを英語文単位で分割し、指定語数以下のチャンクファイルにする。"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


WORD_RE = re.compile(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*")
SENTENCE_RE = re.compile(r".*?(?:\.(?=\s|$)|$)", re.DOTALL)


@dataclass
class Chunk:
    index: int
    text: str
    word_count: int
    path: str


def count_words(text: str) -> int:
    """英数字ベースで英単語数を数える。"""
    return len(WORD_RE.findall(text))


def split_sentences(markdown: str) -> list[str]:
    """Markdownを、翻訳単位として扱いやすい英語文のリストへ分解する。"""
    sentences: list[str] = []
    in_fence = False
    buffer: list[str] = []

    def flush_buffer() -> None:
        """通常テキストのバッファを文単位に切り出して結果へ移す。"""
        nonlocal buffer
        text = "".join(buffer).strip()
        buffer = []
        if not text:
            return
        for match in SENTENCE_RE.finditer(text):
            sentence = match.group(0).strip()
            if sentence:
                sentences.append(sentence)

    for line in markdown.splitlines(keepends=True):
        # コードフェンスの中身は文分割せず、そのまま独立した要素として残す。
        if line.lstrip().startswith("```"):
            flush_buffer()
            in_fence = not in_fence
            sentences.append(line.rstrip("\n"))
            continue

        stripped = line.strip()
        # 画像参照や空行も文へ混ぜず、Markdown構造を保つために単独で扱う。
        if in_fence or stripped.startswith("!") or not stripped:
            flush_buffer()
            if stripped:
                sentences.append(line.rstrip("\n"))
            continue

        buffer.append(line)

    flush_buffer()
    return sentences


def build_chunks(sentences: list[str], max_words: int) -> list[str]:
    """文の順序を保ったまま、最大語数を超えないチャンクへまとめる。"""
    chunks: list[str] = []
    current: list[str] = []
    current_words = 0

    for sentence in sentences:
        words = count_words(sentence)
        if current and current_words + words > max_words:
            chunks.append("\n\n".join(current).strip() + "\n")
            current = []
            current_words = 0

        current.append(sentence)
        current_words += words

    if current:
        chunks.append("\n\n".join(current).strip() + "\n")

    return chunks


def write_chunks(markdown_path: Path, output_dir: Path, max_words: int) -> Path:
    """チャンクファイルと再開用マニフェストを書き出す。"""
    markdown = markdown_path.read_text(encoding="utf-8")
    sentences = split_sentences(markdown)
    chunk_texts = build_chunks(sentences, max_words)

    en_dir = output_dir / "en"
    en_dir.mkdir(parents=True, exist_ok=True)

    manifest_chunks: list[dict[str, object]] = []
    for index, text in enumerate(chunk_texts, start=1):
        chunk_path = en_dir / f"chunk-{index:04d}.md"
        chunk_path.write_text(text, encoding="utf-8")
        manifest_chunks.append(
            {
                "index": index,
                "path": str(chunk_path.relative_to(output_dir).as_posix()),
                "word_count": count_words(text),
            }
        )

    manifest = {
        "source": str(markdown_path),
        "max_words": max_words,
        "chunks": manifest_chunks,
    }
    manifest_path = output_dir / "chunks-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest_path


def main() -> int:
    """コマンドライン引数を読み取り、Markdownのチャンク化を実行する。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown", type=Path, help="Input English Markdown file.")
    parser.add_argument("output_dir", type=Path, help="Output chunks directory.")
    parser.add_argument("--max-words", type=int, default=500, help="Maximum words per chunk.")
    args = parser.parse_args()

    markdown_path = args.markdown.expanduser().resolve()
    if not markdown_path.is_file():
        parser.error(f"Markdown not found: {markdown_path}")
    if args.max_words < 1:
        parser.error("--max-words must be positive")

    manifest_path = write_chunks(markdown_path, args.output_dir.expanduser().resolve(), args.max_words)
    print(manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
