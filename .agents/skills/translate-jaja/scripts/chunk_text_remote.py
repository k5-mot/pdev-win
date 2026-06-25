#!/usr/bin/env python3
"""docling-serveの非同期chunk APIで文書を分割し、翻訳用チャンクへ保存する。"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import time
from pathlib import Path
from typing import Any

from chunk_text import count_words


TEXT_FIELDS = ("text", "content", "chunk_text", "markdown", "md_content")
FAILURE_STATES = {"failure", "failed", "error", "cancelled", "canceled"}


def load_env(env_file: Path | None) -> None:
    """スキル配下、カレントディレクトリ、明示指定の順に.envを読み込む。"""
    try:
        from dotenv import load_dotenv
    except ImportError as exc:
        raise SystemExit(
            "python-dotenv is not installed. Run: python -m pip install -U requests python-dotenv"
        ) from exc

    for path in (Path(__file__).resolve().parents[1] / ".env", Path.cwd() / ".env"):
        if path.is_file():
            load_dotenv(path, override=False)

    if env_file is not None:
        resolved = env_file.expanduser().resolve()
        if not resolved.is_file():
            raise SystemExit(f"Env file not found: {resolved}")
        load_dotenv(resolved, override=True)


def build_headers(api_key: str | None) -> dict[str, str]:
    """docling-serve呼び出しに使うHTTPヘッダーを作る。"""
    headers = {"Accept": "application/json"}
    if api_key:
        headers["X-Api-Key"] = api_key
    return headers


def ensure_ready(base_url: str, headers: dict[str, str], request_timeout: float) -> None:
    """docling-serveのready endpointで利用可能性を確認する。"""
    try:
        import requests
    except ImportError as exc:
        raise SystemExit("requests is not installed. Run: python -m pip install -U requests python-dotenv") from exc

    response = requests.get(f"{base_url}/ready", headers=headers, timeout=request_timeout)
    response.raise_for_status()


def extract_text_from_chunk(chunk: Any) -> str | None:
    """chunkらしいオブジェクトから本文テキストを取り出す。"""
    if isinstance(chunk, str):
        return chunk.strip() or None
    if not isinstance(chunk, dict):
        return None

    for field in TEXT_FIELDS:
        value = chunk.get(field)
        if isinstance(value, str) and value.strip():
            return value.strip()

    enriched = chunk.get("enriched_text")
    if isinstance(enriched, str) and enriched.strip():
        return enriched.strip()

    return None


def collect_chunk_texts(payload: Any) -> list[str]:
    """docling-serveの結果JSONからチャンク本文のリストを抽出する。"""
    if isinstance(payload, dict):
        chunks = payload.get("chunks")
        if isinstance(chunks, list):
            texts = [text for item in chunks if (text := extract_text_from_chunk(item))]
            if texts:
                return texts

        for key in ("document", "result", "results", "data"):
            if key in payload:
                texts = collect_chunk_texts(payload[key])
                if texts:
                    return texts

    if isinstance(payload, list):
        texts: list[str] = []
        for item in payload:
            direct = extract_text_from_chunk(item)
            if direct:
                texts.append(direct)
                continue
            nested = collect_chunk_texts(item)
            if nested:
                texts.extend(nested)
        return texts

    return []


def submit_chunk_job(
    document_path: Path,
    base_url: str,
    headers: dict[str, str],
    request_timeout: float,
    chunker: str,
    from_format: str,
    max_tokens: int | None,
) -> str:
    """chunkingジョブを非同期投入し、task_idを返す。"""
    try:
        import requests
    except ImportError as exc:
        raise SystemExit("requests is not installed. Run: python -m pip install -U requests python-dotenv") from exc

    data: dict[str, object] = {
        "convert_from_formats": [from_format],
        "target_type": "inbody",
        "include_converted_doc": "false",
    }
    if max_tokens is not None:
        data["chunking_max_tokens"] = str(max_tokens)

    media_type = mimetypes.guess_type(document_path.name)[0] or "text/markdown"
    with document_path.open("rb") as fh:
        response = requests.post(
            f"{base_url}/v1/chunk/{chunker}/file/async",
            headers=headers,
            data=data,
            files={"files": (document_path.name, fh, media_type)},
            timeout=request_timeout,
        )
    response.raise_for_status()

    task = response.json()
    task_id = task.get("task_id")
    if not task_id:
        raise SystemExit(f"docling-serve did not return task_id: {task}")
    print(f"docling-serve chunk task submitted: {task_id}", file=sys.stderr)
    return str(task_id)


def wait_for_task(
    task_id: str,
    base_url: str,
    headers: dict[str, str],
    request_timeout: float,
    poll_interval: float,
    max_wait: float,
) -> None:
    """非同期chunkingジョブの完了を待つ。"""
    try:
        import requests
    except ImportError as exc:
        raise SystemExit("requests is not installed. Run: python -m pip install -U requests python-dotenv") from exc

    deadline = time.monotonic() + max_wait
    while True:
        response = requests.get(
            f"{base_url}/v1/status/poll/{task_id}",
            headers=headers,
            timeout=request_timeout,
        )
        response.raise_for_status()
        task = response.json()
        status = str(task.get("task_status") or task.get("status") or "").lower()
        print(f"docling-serve chunk task {task_id}: {status or 'unknown'}", file=sys.stderr)

        if status == "success":
            return
        if status in FAILURE_STATES:
            raise SystemExit(f"docling-serve async chunk task failed: {task}")
        if time.monotonic() >= deadline:
            raise SystemExit(f"docling-serve async chunk task timed out after {max_wait} seconds: {task_id}")
        time.sleep(poll_interval)


def fetch_chunks(
    task_id: str,
    base_url: str,
    headers: dict[str, str],
    request_timeout: float,
) -> list[str]:
    """完了したchunkingジョブの結果を取得し、本文配列へ変換する。"""
    try:
        import requests
    except ImportError as exc:
        raise SystemExit("requests is not installed. Run: python -m pip install -U requests python-dotenv") from exc

    response = requests.get(
        f"{base_url}/v1/result/{task_id}",
        headers=headers,
        timeout=request_timeout,
    )
    response.raise_for_status()
    payload = response.json()
    chunks = collect_chunk_texts(payload)
    if not chunks:
        raise SystemExit(f"docling-serve result did not contain chunks: {json.dumps(payload)[:500]}")
    return chunks


def write_chunks(
    document_path: Path,
    output_dir: Path,
    chunk_texts: list[str],
    max_words: int,
    chunker: str,
) -> Path:
    """チャンクファイルと再開用マニフェストを書き出す。"""
    en_dir = output_dir / "en"
    en_dir.mkdir(parents=True, exist_ok=True)

    manifest_chunks: list[dict[str, object]] = []
    for index, text in enumerate(chunk_texts, start=1):
        chunk_path = en_dir / f"chunk-{index:04d}.md"
        chunk_body = text.rstrip() + "\n"
        chunk_path.write_text(chunk_body, encoding="utf-8")
        manifest_chunks.append(
            {
                "index": index,
                "path": str(chunk_path.relative_to(output_dir).as_posix()),
                "word_count": count_words(chunk_body),
            }
        )

    manifest = {
        "source": str(document_path),
        "max_words": max_words,
        "chunker": f"docling-serve:{chunker}",
        "chunks": manifest_chunks,
    }
    manifest_path = output_dir / "chunks-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest_path


def main() -> int:
    """コマンドライン引数を読み取り、リモートchunkingを実行する。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path, help="Input Markdown or document file.")
    parser.add_argument("output_dir", type=Path, help="Output chunks directory.")
    parser.add_argument("--max-words", type=int, default=500, help="Compatibility value recorded in manifest.")
    parser.add_argument("--max-tokens", type=int, help="Optional docling chunking_max_tokens when supported.")
    parser.add_argument("--chunker", choices=("hierarchical", "hybrid"), default="hierarchical")
    parser.add_argument("--from-format", default="md", help="docling input format, for example md or pdf.")
    parser.add_argument("--env-file", type=Path, help="Optional .env path. Overrides default .env values.")
    parser.add_argument("--base-url", help="docling-serve base URL. Defaults to DOCLING_SERVE_BASE_URL.")
    parser.add_argument("--api-key", help="docling-serve API key. Defaults to DOCLING_SERVE_API_KEY.")
    parser.add_argument("--request-timeout", type=float, default=60.0, help="HTTP timeout per request in seconds.")
    parser.add_argument("--poll-interval", type=float, default=5.0, help="Seconds to wait between async status polls.")
    parser.add_argument("--timeout", type=float, default=86400.0, help="Maximum total wait time for async chunking.")
    args = parser.parse_args()

    load_env(args.env_file)

    document_path = args.document.expanduser().resolve()
    if not document_path.is_file():
        parser.error(f"Document not found: {document_path}")
    if args.max_words < 1:
        parser.error("--max-words must be positive")
    if args.max_tokens is not None and args.max_tokens < 1:
        parser.error("--max-tokens must be positive")

    base_url = (args.base_url or os.environ.get("DOCLING_SERVE_BASE_URL") or "").rstrip("/")
    if not base_url:
        parser.error("DOCLING_SERVE_BASE_URL is not set")

    headers = build_headers(args.api_key or os.environ.get("DOCLING_SERVE_API_KEY"))
    ensure_ready(base_url, headers, args.request_timeout)
    task_id = submit_chunk_job(
        document_path=document_path,
        base_url=base_url,
        headers=headers,
        request_timeout=args.request_timeout,
        chunker=args.chunker,
        from_format=args.from_format,
        max_tokens=args.max_tokens or args.max_words,
    )
    wait_for_task(
        task_id=task_id,
        base_url=base_url,
        headers=headers,
        request_timeout=args.request_timeout,
        poll_interval=args.poll_interval,
        max_wait=args.timeout,
    )
    chunk_texts = fetch_chunks(task_id, base_url, headers, args.request_timeout)
    manifest_path = write_chunks(
        document_path=document_path,
        output_dir=args.output_dir.expanduser().resolve(),
        chunk_texts=chunk_texts,
        max_words=args.max_words,
        chunker=args.chunker,
    )
    print(manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
