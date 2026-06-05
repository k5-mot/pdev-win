# 🧑‍💻 Coding Rules

このリポジトリの PowerShell / shell / Markdown ファイルに適用するコーディング規約です。

## 1. 📝 共通ルール

- テキストファイルは UTF-8 without BOM で保存する。
- 改行コードは既存ファイルに合わせる。新規ファイルは LF を基本とする。
- パスは固定のユーザープロファイルパスに依存しない。
- Desktop などの既知フォルダーは `[Environment]::GetFolderPath()` で解決する。
- ユーザーまたはシステム PATH 上の同名ツールを拾わないよう、検証時は Root から組み立てた実体パスを優先する。
- 複数行にわたるコマンド例には、各コマンドが何をするか分かる説明コメントを付ける。

## 2. ⚡ PowerShell

- コメントは日本語で書く。
- 関数には comment-based help を必ず付ける。
- comment-based help は Microsoft Learn の構文に従う。
  - 参考: [about_Comment_Based_Help](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_comment_based_help?view=powershell-7.6#syntax-for-comment-based-help-in-functions)
- 関数コメントには少なくとも `.SYNOPSIS` を含める。
- 引数を持つ関数では、必要に応じて `.PARAMETER` を書く。
- 戻り値や副作用が分かりにくい関数では、必要に応じて `.OUTPUTS`、`.NOTES`、`.EXAMPLE` を書く。
- 複雑な処理には、読み手の判断を助ける短い日本語コメントを入れる。
- `Set-StrictMode` と `$ErrorActionPreference = 'Stop'` を基本とする。
- 外部コマンド実行時は終了コードを確認する。
- 一時ファイル、ログ、キャッシュは portable Root 配下に寄せる。
- AppData やシステム全体の設定変更に依存しない。

関数コメントの例:

```powershell
<#
.SYNOPSIS
指定されたディレクトリを作成します。
.PARAMETER Path
作成するディレクトリのパスです。
#>
function New-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}
```

## 3. 🐚 Shell

- `set -euo pipefail` を基本とする。
- 失敗時のメッセージは標準エラーへ出す。
- 入力ファイルや出力ファイルの存在確認を行う。
- 破壊的な処理は明示的な条件確認をしてから行う。

## 4. 📚 Markdown

- README は入口として簡潔に保つ。
- 詳細仕様は `docs/SPEC.md` に集約する。
- Troubleshooting は `docs/TROUBLESHOOTING.md` に集約する。
- 見出しには必要に応じて絵文字を使い、読みやすさを優先する。
- コマンド例は実行可能な形にし、複数行の場合は説明コメントを付ける。

## 5. 🌱 Git Commit

- コミットメッセージは日本語で書く。
- Conventional Commits の形式に従う。
- 先頭に gitmoji を付ける。
- 形式は `<gitmoji> <type>: <summary>` とする。
- 代表的な `type` は `feat`、`fix`、`docs`、`refactor`、`test`、`chore` を使う。
- 1 コミットは意味のある作業単位にまとめる。
- 変更内容が混ざる場合は、ドキュメント、実装、リネームなどでコミットを分ける。

例:

```text
📝 docs: README と仕様書を整理
♻️ refactor: セットアップスクリプトを現行版へ差し替え
✅ test: image download の検証手順を追加
```
