---
name: translate-jaja
description: 英語PDFを日本語Markdownへ段階的に翻訳する。Doclingまたはdocling-serveでMarkdownと画像アセットを抽出し、翻訳しやすいチャンクへ分割してから、OpenAI互換APIで日本語化する場合に使う。
---

# 英語PDFを日本語Markdownへ翻訳する

## 作業手順

1. 利用中のPython環境に依存パッケージを入れます。

```bash
python -m pip install -U docling openai python-dotenv requests
```

2. `.env` にOpenAI互換APIとdocling-serveの設定を書きます。各スクリプトは、スキルディレクトリの `.env`、カレントディレクトリの `.env`、明示指定した `--env-file` の順で読み込みます。明示指定した値が最優先です。

```bash
OPENAI_BASE_URL=http://localhost:40000
OPENAI_API_KEY=sk-litellm-master-key
OPENAI_MODEL=gemma4:31b
DOCLING_SERVE_BASE_URL=http://localhost:50000
DOCLING_SERVE_API_KEY=sk-docling-serve-api-key
```

3. 英語PDFをMarkdownと画像アセットへ変換します。`DOCLING_SERVE_BASE_URL` が設定され、docling-serveコンテナが起動している場合は、まずremote版を使います。

```bash
python /path/to/translate-jaja/scripts/convert_to_md_remote.py /path/to/source.pdf /path/to/workdir
```

remote版は `POST /v1/convert/file/async` へジョブを投入し、`/v1/status/poll/{task_id}` で完了を待ち、`/v1/result/{task_id}` のzip結果から `workdir/document.md` と参照画像を取り出します。

docling-serveが使えない場合は、ローカルDoclingへ切り替えます。

```bash
python /path/to/translate-jaja/scripts/convert_to_md.py /path/to/source.pdf /path/to/workdir
```

4. Markdownを翻訳用チャンクへ分割します。docling-serveが利用可能なら、remote chunkingを優先します。

```bash
python /path/to/translate-jaja/scripts/chunk_text_remote.py /path/to/workdir/document.md /path/to/workdir/chunks --max-words 500
```

`chunk_text_remote.py` は既定で `POST /v1/chunk/hierarchical/file/async` を使い、`chunks/en/chunk-0001.md` と `chunks-manifest.json` を作成します。サーバーと入力形式が対応している場合にhybrid chunkerを使うには `--chunker hybrid` を指定します。

docling-serveが使えない場合は、ローカルの文単位chunkingを使います。

```bash
python /path/to/translate-jaja/scripts/chunk_text.py /path/to/workdir/document.md /path/to/workdir/chunks --max-words 500
```

5. チャンクを順番に翻訳し、最終的な日本語Markdownを組み立てます。

```bash
python /path/to/translate-jaja/scripts/translate_ja.py /path/to/workdir/chunks /path/to/workdir/document.ja.md
```

`translate_ja.py` は1チャンクずつ翻訳し、`chunks/ja/chunk-0001.ja.md` 形式の途中成果物を保存します。途中で止まった場合も同じコマンドで再開できます。既存の翻訳済みチャンクを作り直す場合は `--force` を指定します。

既定では `assets/glossary.csv` を読み、`english,japanese,notes` の用語対応を優先します。別の用語集を使う場合は `--glossary /path/to/glossary.csv`、用語集を使わない場合は `--no-glossary` を指定します。

## 翻訳ルール

- Markdownの構造、見出し、表、リスト、コードフェンス、インラインコード、リンク、画像参照を保つ。
- 英語の本文は自然な日本語へ翻訳する。
- `assets/glossary.csv` の用語を優先する。
- 製品名、識別子、コマンド、ファイルパス、URL、コードは、明確な定訳がある場合を除き英語のまま残す。
- 日本語の技術文書として読みやすい文体に統一する。
- API資格情報がない、API呼び出しに失敗した、最終Markdownに未翻訳の英語本文が残っている、という状態では完了と見なさない。

## 同梱スクリプト

- `scripts/convert_to_md.py`: ローカルDoclingでPDFを `document.md` へ変換する。
- `scripts/convert_to_md_remote.py`: docling-serveの `POST /v1/convert/file/async` でPDFをMarkdownと画像アセットへ変換する。
- `scripts/chunk_text_remote.py`: docling-serveの `POST /v1/chunk/{path_name}/file/async` で文書を分割し、標準manifestを書き出す。
- `scripts/chunk_text.py`: Markdownを英語文単位で分割し、語数上限付きチャンクへまとめる。
- `scripts/translate_ja.py`: チャンクをOpenAI互換APIで翻訳し、日本語Markdownを逐次組み立てる。
