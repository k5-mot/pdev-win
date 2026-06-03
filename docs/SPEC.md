# 仕様: Desktop 配下に構築するポータブル開発環境

## 目的

管理者権限を使わず、社内ポリシーでアクセス可能な `Desktop` 配下だけを利用して、以下のツールをポータブルにインストールする PowerShell スクリプトを作成する。

- Python
- Node.js
- pip
- uv
- jq
- pandoc
- Visual Studio Code
- Cygwin

インストール後は各ツールを PATH に追加し、利用可能であることを検証する。

## 実行環境と制約

- 管理者権限は使用しない。
- アクセス可能なディレクトリは社内ポリシーにより制限されている。
- `Downloads` と `Desktop` は利用可能。
- `AppData` やユーザホーム直下の `.local` など、`Desktop` 外のディレクトリにはアクセスできない前提とする。
- すべてのバイナリ、ユーザデータ、設定、キャッシュは `Desktop` 配下に配置する。
- 追加の格納先が必要な場合は、事前にユーザへ相談する。

## ディレクトリ構成

基準ディレクトリは `Desktop` 配下とする。

```text
Desktop/
  .local/
    opt/
      jq/
      vscode/
      python/
      nodejs/
      uv/
      pandoc/
      cygwin/
    pkg/
      downloaded-archives/
    logs/
    tmp/
  .config/
    vscode/
    cygwin/
    powershell/
  VSCode.bat
  Cygwin.bat
```

### `.local/opt`

解凍済みのバイナリ、パッケージ、ツール本体を格納する。

### `.local/pkg`

ダウンロードした zipball、アーカイブ、wheel などをキャッシュする。

### `.local/logs`

実行ログを格納する。

### `.local/tmp`

zip 展開などの一時ファイルを格納する。

### `.config`

設定ファイル、ユーザデータ、ツール固有の設定を格納する。

## PowerShell スクリプト要件

PowerShell スクリプトは以下を実行する。

1. 必要なディレクトリを作成する。
2. 指定されたバージョンのツールをダウンロードする。
3. ダウンロード済みアーカイブが存在する場合は `.local/pkg` のキャッシュを利用する。
4. 各ツールを `.local/opt/{tool}` 配下に展開またはインストールする。
5. PATH を構成する。
6. 各ツールが PATH から呼び出せることを検証する。
7. VS Code 起動用の `VSCode.bat` を `$Root` 直下に生成する。
8. Cygwin 起動用の `Cygwin.bat` を `$Root` 直下に生成する。
9. VS Code のターミナルから Cygwin を呼び出せるように設定する。

## 引数

PowerShell スクリプトでは、`$Root` を基準にすべてのインストール先を決定する。

各ツールの個別インストール先を指定する引数は用意しない。

### 基本引数

- `Root`
  - ポータブル開発環境の基準ディレクトリ。
  - 必須引数とする。
  - `Desktop` 配下のパスを指定する。

### バージョン指定引数

以下のツールはバージョンを引数指定できるようにする。

- Python
- Node.js
- uv
- jq
- pandoc
- Visual Studio Code

### Cygwin 引数

Cygwin については、インストールするパッケージ一覧のみ引数指定できるようにする。

- `CygwinPackages`

Cygwin 本体のインストール先は `$Root/.local/opt/cygwin` で固定する。

Cygwin mirror は以下の国内候補から疎通できるものを選択する。

- `https://ftp.jaist.ac.jp/pub/cygwin/`
- `https://ftp.yamagata-u.ac.jp/pub/cygwin/`
- `https://ftp.iij.ad.jp/pub/cygwin/`

上記 3 つにアクセスできない場合は、`https://mirrors.kernel.org/sourceware/cygwin/` を選択する。

Cygwin setup は以下の方針で実行する。

- インターネットからインストールする。
- `--no-admin` により現在のユーザのみへインストールする。
- システムのプロキシ設定を使用する。

### pip

pip は wheel からインストールする。

`PipVersion` 引数は用意しない。

## VS Code 要件

VS Code はポータブル構成で起動できるようにする。

- VS Code 本体は `.local/opt/vscode` に配置する。
- VS Code のユーザデータや設定は `Desktop/.config/vscode` 配下に配置する。
- `--no-gpu` と `--no-sandbox` を指定して起動できるようにする。
- VS Code の integrated terminal から Cygwin を呼び出せるようにする。

`SkipVSCodeLaunch` 引数は用意しない。

## 起動コマンド要件

PowerShell スクリプト内で `$Root/VSCode.bat` と `$Root/Cygwin.bat` を作成する。

起動コマンドは以下を満たす。

- PATH をポータブル環境向けに設定する。
- `code.exe` を起動する。
- `--no-gpu` と `--no-sandbox` を指定して VS Code を起動する。
- VS Code 起動後はコンソールを表示し続けない。
- `start /min` などを利用し、コンソール表示を抑制する。
- `start.bat`、`start.cmd`、`bin/start.cmd`、`launch-vscode.ps1` は生成しない。
- `Cygwin.bat` は `$Root/.local/opt/cygwin/bin` に移動して `bash --login -i` を起動する。
- インストール完了後、VS Code は自動起動しない。
- インストール完了後、`$Root/VSCode.bat` による起動方法をログに表示する。

## ログ要件

処理中は適宜ログを出力する。

ログは以下の要素を含め、見やすくする。

- 時刻
- ログレベルまたは処理名
- 色付き表示
- 絵文字

## コメント要件

- 関数には必ず日本語の comment-based help を付ける。
- 関数コメントは PowerShell の `about_Comment_Based_Help` に準拠する。
- 関数コメントでは `<# ... #>` ブロック内に `.SYNOPSIS`、必要に応じて `.DESCRIPTION`、`.PARAMETER`、`.OUTPUTS`、`.EXAMPLE` などを記述する。
- 関数コメントは関数本体の先頭、関数本体の末尾、または `function` キーワードの直前に配置する。
- 複雑な処理にも適宜日本語コメントを入れる。
- 保守しやすい構成にする。

## 検証要件

インストール後、以下を検証する。

- 各ツールが PATH に含まれていること。
- 各ツールのバージョンコマンドが実行できること。
- VS Code が生成された起動バッチから起動できること。
- VS Code の integrated terminal から Cygwin が呼び出せること。

## 未決事項

以下は実装前に確認が必要な項目。

- 基準ディレクトリの正確な名前。
  - 例: `Desktop/.portable-dev`、`Desktop/pdev-win`、`Desktop/.local`
- `Downloads` をダウンロード先として使うか、すべて `Desktop/.local/pkg` に集約するか。
- 各ツールのデフォルトバージョン。
- Cygwin のインストール方式。
  - 例: 既存の zipball を利用する、`setup-x86_64.exe` をポータブル用途で利用する。
- VS Code の拡張機能を事前インストールするか。
- プロキシ設定や証明書設定が必要か。
