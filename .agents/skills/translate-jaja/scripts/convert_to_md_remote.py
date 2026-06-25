#!/usr/bin/env python3
"""docling-serveの非同期APIでPDFをMarkdownと画像アセットへ変換する。"""

from __future__ import annotations

import argparse
import io
import mimetypes
import os
import sys
import time
import zipfile
from pathlib import Path

FULL_CONVERSION_OPTIONS = {
    ### 入力形式.
    "from_formats": ["pdf"],
    ### 出力形式.
    "to_formats": ["md"],
    ### 画像アセット出力形式.
    "target_type": "zip",
    ### 画像埋め込み形式.
    "image_export_mode": "referenced",
    ### 図表切り出し画像.
    "include_images": "true",
    ### ページ全体画像
    "include_page_images": "false",
    ### 画像を書き出す解像度倍率.
    "images_scale": "2.0",
    ### 文書構造解析 有効化.
    # "layout_preset": "layout",
    ### 表構造解析 有効化.
    "do_table_structure": "true",
    "table_cell_matching": "true",
    "table_mode": "accurate",
    # "table_structure_preset": "tableformerv2",
    ### 画像・図分類 有効化.
    "do_picture_classification": "true",
    # "picture_classification_preset": "picture_classifier",
    ### OCRエンジン 有効化.
    "do_ocr": "true",
    "force_ocr": "false",
    "ocr_preset": "tesseract",
    "ocr_lang": ["jpn", "jpn_vert", "eng"],
    # ### 画像・図説明生成VLM 有効化.
    # "do_picture_description": "true",
    # # "picture_description_preset": "smolvlm",
    # "picture_description_preset": "granite_vision",
    # ### コード・数式VLM 有効化.
    # "do_code_enrichment": "true",
    # "do_formula_enrichment": "true",
    # "code_formula_preset": "code_formula",
    # ### グラフ数値抽出VLM 有効化.
    # "do_chart_extraction": "true",
}


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


def extract_zip(content: bytes, output_dir: Path, output_name: str) -> Path:
    """docling-serveのzip結果を展開し、Markdownファイルのパスを返す。"""
    output_dir.mkdir(parents=True, exist_ok=True)
    output_root = output_dir.resolve()
    markdown_files: list[Path] = []

    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        for member in archive.infolist():
            if member.is_dir():
                continue

            target = (output_dir / member.filename).resolve()
            try:
                # zip内の相対パスが出力ディレクトリ外へ抜けないことだけ確認する。
                target.relative_to(output_root)
            except ValueError as exc:
                raise SystemExit(f"Unsafe zip path from docling-serve: {member.filename}") from exc

            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as src, target.open("wb") as dst:
                dst.write(src.read())

            if target.suffix.lower() in {".md", ".markdown"}:
                markdown_files.append(target)

    if not markdown_files:
        raise SystemExit("docling-serve returned a zip, but no Markdown file was found.")

    md_path = output_dir / output_name
    source = next((path for path in markdown_files if path.name == output_name), markdown_files[0])
    if source.resolve() != md_path.resolve():
        if md_path.exists():
            md_path.unlink()
        source.replace(md_path)
    return md_path


def convert_pdf(
    pdf_path: Path,
    output_dir: Path,
    output_name: str,
    base_url: str,
    api_key: str | None,
    request_timeout: float,
    poll_interval: float,
    max_wait: float,
    options: dict[str, str],
) -> Path:
    """PDFを非同期ジョブとして投入し、完了後のzip結果を保存する。"""
    try:
        import requests
    except ImportError as exc:
        raise SystemExit("requests is not installed. Run: python -m pip install -U requests python-dotenv") from exc

    headers = {"Accept": "application/zip, application/json"}
    if api_key:
        headers["X-Api-Key"] = api_key

    media_type = mimetypes.guess_type(pdf_path.name)[0] or "application/pdf"
    with pdf_path.open("rb") as fh:
        response = requests.post(
            f"{base_url}/v1/convert/file/async",
            headers=headers,
            data=options,
            files={"files": (pdf_path.name, fh, media_type)},
            timeout=request_timeout,
        )
    response.raise_for_status()

    task = response.json()
    task_id = task.get("task_id")
    if not task_id:
        raise SystemExit(f"docling-serve did not return task_id: {task}")
    print(f"docling-serve task submitted: {task_id}", file=sys.stderr)

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
        print(f"docling-serve task {task_id}: {status or 'unknown'}", file=sys.stderr)

        if status == "success":
            break
        if status in {"failure", "failed", "error", "cancelled", "canceled"}:
            raise SystemExit(f"docling-serve async task failed: {task}")
        if time.monotonic() >= deadline:
            raise SystemExit(f"docling-serve async task timed out after {max_wait} seconds: {task_id}")
        time.sleep(poll_interval)

    response = requests.get(
        f"{base_url}/v1/result/{task_id}",
        headers=headers,
        timeout=request_timeout,
    )
    response.raise_for_status()
    if not response.content.startswith(b"PK\x03\x04"):
        raise SystemExit(f"docling-serve result was not a zip response: {response.text[:500]}")
    return extract_zip(response.content, output_dir, output_name)


def main() -> int:
    """コマンドライン引数を読み取り、リモートPDF変換を実行する。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Input English PDF path.")
    parser.add_argument("output_dir", type=Path, help="Directory for Markdown and image assets.")
    parser.add_argument("--output-name", default="document.md", help="Markdown filename.")
    parser.add_argument("--env-file", type=Path, help="Optional .env path. Overrides default .env values.")
    parser.add_argument("--base-url", help="docling-serve base URL. Defaults to DOCLING_SERVE_BASE_URL.")
    parser.add_argument("--api-key", help="docling-serve API key. Defaults to DOCLING_SERVE_API_KEY.")
    parser.add_argument("--request-timeout", type=float, default=60.0, help="HTTP timeout per request in seconds.")
    parser.add_argument("--poll-interval", type=float, default=5.0, help="Seconds to wait between async status polls.")
    parser.add_argument("--timeout", type=float, default=86400.0, help="Maximum total wait time for async conversion.")
    args = parser.parse_args()

    load_env(args.env_file)

    pdf_path = args.pdf.expanduser().resolve()
    if not pdf_path.is_file():
        parser.error(f"PDF not found: {pdf_path}")

    base_url = (args.base_url or os.environ.get("DOCLING_SERVE_BASE_URL") or "").rstrip("/")
    if not base_url:
        parser.error("DOCLING_SERVE_BASE_URL is not set")

    options = dict(FULL_CONVERSION_OPTIONS)

    md_path = convert_pdf(
        pdf_path=pdf_path,
        output_dir=args.output_dir.expanduser().resolve(),
        output_name=args.output_name,
        base_url=base_url,
        api_key=args.api_key or os.environ.get("DOCLING_SERVE_API_KEY"),
        request_timeout=args.request_timeout,
        poll_interval=args.poll_interval,
        max_wait=args.timeout,
        options=options,
    )
    print(md_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
