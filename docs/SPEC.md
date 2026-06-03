# 仕様: Desktop 配下に構築するポータブル開発環境

この仕様は `setup.ps1` の現在の実装を正として記述する。

## 目的

管理者権限を使わず、`Desktop` 配下だけを利用して以下のツールをポータブルにインストールする。

- Python
- pip
- Node.js
- uv
- jq
- pandoc
- Visual Studio Code
- Cygwin

インストール後は PATH を構成し、各ツールが利用可能であることを検証する。VS Code と Cygwin は `$Root` 直下に生成されるバッチファイルから起動する。

## 実行環境と制約

- Windows PowerShell 5+ を想定する。
- 管理者権限は使用しない。
- `$Root` は `Desktop` 配下でなければならない。
- `Desktop` 配下以外を指定した場合は停止する。
- すべてのバイナリ、ユーザーデータ、設定、キャッシュ、ログ、一時ファイルは `$Root` 配下に配置する。
- インストール時に GitHub、Python.org、Node.js、PyPI、VS Code update endpoint、Cygwin mirror へアクセスする。

## ディレクトリ構成

既定の基準ディレクトリは `%USERPROFILE%\Desktop\pdev` とする。

```text
pdev/
  .local/
    opt/
      python/
      nodejs/
      uv/
      jq/
      pandoc/
      vscode/
        data/
          user-data/User/
            settings.json
            extensions.json
          extensions/
      cygwin/
    pkg/
      cygwin/
      pip-cache/
      uv-cache/
      npm-cache/
    logs/
    tmp/
  .config/
    pip/
      pip.ini
  VSCode.bat
  Cygwin.bat
```

### `.local/opt`

展開済みのツール本体を格納する。

### `.local/pkg`

ダウンロードした zip、exe、wheel と、各種パッケージキャッシュを格納する。

### `.local/logs`

`install-*.log` を格納する。

### `.local/tmp`

zip 展開などの一時ファイルを格納する。

### `.config`

pip 設定を格納する。

## 引数

### `Root`

- ポータブル開発環境の基準ディレクトリ。
- 既定値は `%USERPROFILE%\Desktop\pdev`。
- `Desktop` 配下のパスのみ許可する。

### バージョン指定引数

以下のツールはバージョンを引数指定できる。

| 引数 | 既定値 |
| --- | --- |
| `PythonVersion` | `3.12.10` |
| `NodeVersion` | `24.16.0` |
| `UvVersion` | `0.11.18` |
| `JqVersion` | `1.8.0` |
| `PandocVersion` | `3.9.0.2` |
| `VSCodeVersion` | `stable` |

`NodeVersion` と `UvVersion` は `v` 接頭辞の有無を許容する。`JqVersion` は `jq-` 接頭辞の有無を許容する。

### Cygwin 引数

- `CygwinPackages`
  - 既定値は `bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux`。
  - Cygwin 本体のインストール先は `$Root\.local\opt\cygwin`。

### その他

- `Force`
  - 既存キャッシュや展開先を上書きして再実行する。

`PipVersion` や `SkipVSCodeLaunch` は用意しない。

## PowerShell スクリプト要件

PowerShell スクリプトは以下を実行する。

1. TLS 1.2 を有効化する。未対応環境では既定設定のまま続行する。
2. `$Root` と各ディレクトリが `Desktop` 配下であることを検証する。
3. 必要なディレクトリを作成する。
4. 指定されたバージョンのツールをダウンロードする。
5. ダウンロード済みファイルが存在し、`-Force` が指定されていない場合は `.local/pkg` のキャッシュを利用する。
6. 各ツールを `.local/opt/{tool}` 配下に展開または配置する。
7. Python embeddable zip の `python*._pth` で `import site` を有効化する。
8. PyPI JSON から pip wheel を取得し、wheel から pip をインストールする。
9. pip 用の `.config\pip\pip.ini` を生成する。
10. Cygwin mirror を選択し、公式 `setup-x86_64.exe` を CLI 実行する。
11. VS Code portable mode 用の `data` ディレクトリを作成する。
12. VS Code settings と extensions recommendation を生成する。
13. VS Code CLI で拡張機能を portable extensions dir にインストールする。
14. 現プロセスの PATH とキャッシュ関連環境変数を構成する。
15. `$Root\VSCode.bat` と `$Root\Cygwin.bat` を生成する。
16. 各ツールが PATH から呼び出せることと、バージョンコマンドが実行できることを検証する。

## pip 要件

- pip は `get-pip.py` ではなく PyPI から取得した wheel でインストールする。
- `pip.ini` には `disable-pip-version-check = true` を設定する。
- pip のキャッシュは `PIP_CACHE_DIR` 環境変数で `$Root\.local\pkg\pip-cache` に向ける。

## VS Code 要件

- VS Code 本体は `$Root\.local\opt\vscode` に配置する。
- VS Code は portable mode を使い、ユーザーデータは `$Root\.local\opt\vscode\data\user-data` に置く。
- 拡張機能は `$Root\.local\opt\vscode\data\extensions` にインストールする。
- `settings.json` は `$Root\.local\opt\vscode\data\user-data\User\settings.json` に生成する。
- `extensions.json` は `$Root\.local\opt\vscode\data\user-data\User\extensions.json` に生成する。
- integrated terminal の既定プロファイルは `PowerShell-Portable` とする。
- integrated terminal から `Cygwin` プロファイルを選べるようにする。
- `workbench.colorTheme` は `Visual Studio Dark` とする。
- `window.commandCenter` は無効化する。
- `chat.titleBar.signIn.enabled` は無効化する。
- `chat.disableAIFeatures` は有効化する。

## VS Code 拡張機能

以下を推奨拡張として書き込み、同時に portable extensions dir へインストールする。

- `ZooCodeOrganization.zoo-code`
- `zhuangtongfa.Material-theme`
- `openai.chatgpt`
- `anthropic.claude-code`

## Cygwin 要件

Cygwin は公式 `setup-x86_64.exe` を使ってインストールする。Cygwin は rolling distribution のため、任意の過去バージョン固定は保証しない。

Cygwin mirror は以下の国内候補から疎通できるものを選択する。

- `https://ftp.jaist.ac.jp/pub/cygwin/`
- `https://ftp.yamagata-u.ac.jp/pub/cygwin/`
- `https://ftp.iij.ad.jp/pub/cygwin/`

上記 3 つにアクセスできない場合は、`https://mirrors.kernel.org/sourceware/cygwin/` を選択する。

Cygwin setup は以下の引数で実行する。

- `--quiet-mode`
- `--no-admin`
- `--only-site`
- `--root`
- `--local-package-dir`
- `--site`
- `--packages`

setup の `net-method` は `IE5` に設定し、システムのプロキシ設定を使う。

## 起動コマンド要件

PowerShell スクリプト内で `$Root\VSCode.bat` と `$Root\Cygwin.bat` を作成する。

### `VSCode.bat`

- ランチャー内で PATH をポータブル環境向けに設定する。
- `PIP_CONFIG_FILE`、`PIP_CACHE_DIR`、`UV_CACHE_DIR`、`npm_config_cache` を設定する。
- `CODEX_HOME`、`CODEX_SQLITE_HOME`、`LITELLM_API_KEY` を設定する。必要なディレクトリは利用するツール側で作成される想定とする。
- `Code.exe` を `start "" /min` で起動する。
- `--user-data-dir` と `--extensions-dir` を指定する。
- `--disable-gpu` と `--no-sandbox` を指定する。
- 起動後は `exit /b 0` で終了する。

### `Cygwin.bat`

- `$Root\.local\opt\cygwin\bin` に移動する。
- `bash --login -i` を起動する。

インストール完了後、VS Code は自動起動しない。ログに `$Root\VSCode.bat` と `$Root\Cygwin.bat` のパスを表示する。

## ログ要件

処理中は適宜ログを出力する。

ログは以下を含む。

- 時刻
- ログレベル
- メッセージ
- コンソール表示時の色

ログレベルは `INFO`、`OK`、`WARN`、`ERROR`、`STEP` とする。

## コメント要件

- 関数には日本語の comment-based help を付ける。
- 関数コメントは PowerShell の [about_Comment_Based_Help](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_comment_based_help?view=powershell-7.6#syntax-for-comment-based-help-in-functions) に準拠する。
- 関数コメントでは `<# ... #>` ブロック内に `.SYNOPSIS`、必要に応じて `.PARAMETER`、`.OUTPUTS` などを記述する。
- 複雑な処理には適宜日本語コメントを入れる。

## 検証要件

インストール中に以下を検証する。

- 各ツールが PATH から見つかること。
- 各ツールのバージョンコマンドが実行できること。

手動検証手順は [TESTING.md](TESTING.md) に記載する。
