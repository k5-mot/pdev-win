# 📘 Specification

この仕様は `setup_v4.ps1` の現在の実装を正として記述する。

## 1. 🎯 目的

管理者権限を使わず、`Desktop` 配下だけを利用して以下のツールをポータブルにインストールする。

- Python
- pip
- Node.js
- uv
- jq
- pandoc
- bat
- bottom
- delta
- dust
- eza
- fd
- genact
- hyperfine
- procs
- ripgrep
- Visual Studio Code
- Cygwin

インストール後は PATH を構成し、各ツールが利用可能であることを検証する。VS Code、Cygwin、PowerShell は `$Root` 直下に生成されるランチャーから起動する。

## 2. 🧭 実行環境と制約

- Windows PowerShell 5+ を想定する。
- 管理者権限は使用しない。
- 既定の `$Root` は OS の既知フォルダー API から解決した `Desktop` 配下とする。
- `$Root` は検証済みの `Desktop` 配下でなければならない。
- `Desktop` 配下以外を指定した場合は停止する。
- ユーザーフォルダーはリダイレクトやネットワーク配置の可能性があるため、ユーザープロファイル配下の物理パスをハードコードしない。
- ユーザーフォルダーへアクセスできない状態ではセットアップを継続できない場合があるため、ネットワークパスを検出した場合は注意を促す。
- AppData など既定ユーザー領域への設定・キャッシュ書き込みに依存しない。
- バイナリ、ユーザーデータ、設定、キャッシュ、ログ、一時ファイルは原則として `$Root` 配下に配置する。
- ランチャーはネットワークパスでも起動できるよう、実行前に作業ディレクトリを確立する。
- 検証時はユーザーまたはシステム PATH 上の同名ツールではなく、検証済み `$Root` から組み立てた実体パスを優先する。
- インストール時に GitHub、Python.org、Node.js、PyPI、VS Code update endpoint、Cygwin mirror へアクセスする。

## 3. 🗂️ ディレクトリ構成

既定の基準ディレクトリは、OS から解決した `Desktop` 配下の `pdev` とする。

```text
pdev/
  .local/
    opt/
      python/
      nodejs/
      uv/
      jq/
      pandoc/
      bat/
      bottom/
      delta/
      dust/
      eza/
      fd/
      genact/
      hyperfine/
      procs/
      ripgrep/
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
  VSCode.cmd
  Cygwin.cmd
  PowerShell.cmd
```

Root 直下にはランチャーのみを置き、ツール本体、設定、キャッシュ、ログ、一時ファイルは `$Root` 配下のサブディレクトリへ分ける。

### 3.1 `.local/opt`

展開済みのツール本体を格納する。

### 3.2 `.local/pkg`

ダウンロードした zip、exe、wheel と、各種パッケージキャッシュを格納する。

### 3.3 `.local/logs`

`install-*.log` を格納する。

### 3.4 `.local/tmp`

zip 展開などの一時ファイルを格納する。

### 3.5 `.config`

pip 設定を格納する。

## 4. ⚙️ 導入方法

リモートから直接実行する場合:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup_v4.ps1'))"
```

ローカルのリポジトリから実行する場合:

```powershell
# ローカルの setup_v4.ps1 を実行し、Desktop 配下へ Root を作成する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_v4.ps1 `
  -Root (Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev')
```

`-Root` を指定する場合も、解決後のパスは Desktop 配下でなければならない。

## 5. 🧾 引数

### 5.1 `Root`

- ポータブル開発環境の基準ディレクトリ。
- 既定値は OS から解決した `Desktop` 配下の `pdev`。
- `Desktop` 配下のパスのみ許可する。

### 5.2 バージョン指定引数

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

### 5.3 Cygwin 引数

- `CygwinPackages`
  - 既定値は `bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux`。
  - Cygwin 本体のインストール先は `$Root\.local\opt\cygwin`。

### 5.4 その他

- `Force`
  - 既存キャッシュや展開先を上書きして再実行する。

`PipVersion` や `SkipVSCodeLaunch` は用意しない。

## 6. 🧪 PowerShell スクリプト要件

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
10. GitHub Releases から portable CLI tools の Windows x64 asset を取得し、`.local\opt` 配下に展開または配置する。
11. VS Code portable mode 用の `data` ディレクトリを作成する。
12. Cygwin mirror を選択し、公式 `setup-x86_64.exe` を CLI 実行する。
13. 現プロセスの PATH とキャッシュ関連環境変数を構成する。
14. VS Code settings と extensions recommendation を生成する。
15. VS Code CLI で拡張機能を portable extensions dir にインストールする。
16. `$Root\VSCode.cmd`、`$Root\Cygwin.cmd`、`$Root\PowerShell.cmd` を生成する。
17. pip と npm の追加パッケージをインストールする。
18. 各ツールの実体パスが存在し、バージョンコマンドが実行できることを検証する。

## 7. 🐍 pip 要件

- pip は `get-pip.py` ではなく PyPI から取得した wheel でインストールする。
- Python embeddable 環境で安定して動作するよう、pip wheel は site-packages へ直接展開する。
- `_pth` ファイルは pip と追加パッケージを import できるように調整する。
- pip 起動用に `Scripts\pip.cmd` を生成し、`python -m pip` を呼び出す。
- `pip.ini` には `disable-pip-version-check = true` を設定する。
- pip のキャッシュは `PIP_CACHE_DIR` 環境変数で `$Root\.local\pkg\pip-cache` に向ける。
- 追加パッケージとして `setuptools`、`wheel`、`python-docx`、`pypdf`、`Pillow` をインストールする。

## 8. 📦 npm 要件

- npm の cache と prefix は `$Root` 配下に向ける。
- 追加パッケージとして `npm` と `cowsay` をグローバルインストールする。

## 9. 🧩 VS Code 要件

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

## 10. 🧱 VS Code 拡張機能

以下を推奨拡張として書き込み、同時に portable extensions dir へインストールする。

- `ZooCodeOrganization.zoo-code`
- `zhuangtongfa.Material-theme`
- `openai.chatgpt`
- `anthropic.claude-code`

## 11. 🐚 Cygwin 要件

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

## 12. 🚀 起動コマンド要件

PowerShell スクリプト内で `$Root\VSCode.cmd`、`$Root\Cygwin.cmd`、`$Root\PowerShell.cmd` を作成する。

### 12.1 `VSCode.cmd`

- ランチャー内で PATH をポータブル環境向けに設定する。
- `PIP_CONFIG_FILE`、`PIP_CACHE_DIR`、`UV_CACHE_DIR`、`npm_config_cache` を設定する。
- `CODEX_HOME`、`CODEX_SQLITE_HOME`、`LITELLM_API_KEY` を設定する。必要なディレクトリは利用するツール側で作成される想定とする。
- `Code.exe` を `start "" /min` で起動する。
- `--user-data-dir` と `--extensions-dir` を指定する。
- `--disable-gpu` と `--no-sandbox` を指定する。
- 起動後は `exit /b 0` で終了する。

### 12.2 `Cygwin.cmd`

- `$Root\.local\opt\cygwin\bin` に移動する。
- `bash --login -i` を起動する。

### 12.3 `PowerShell.cmd`

- ランチャー内で PATH とキャッシュ関連環境変数をポータブル環境向けに設定する。
- Windows PowerShell を起動する。

インストール完了後、VS Code は自動起動しない。ログに各ランチャーのパスを表示する。

## 13. 🪟 Windows Terminal 連携

Windows Terminal を使う場合は、既存の `settings.json` に `PowerShell-Portable` と `Cygwin` のプロファイルを追加できる。

- `PowerShell-Portable` は `$Root\PowerShell.cmd` を起動する。
- `Cygwin` は `$Root\Cygwin.cmd` を起動する。
- `startingDirectory` は実際の `$Root` に合わせる。
- 既存プロファイルは残し、必要なプロファイルだけ追加する。

## 14. 📝 ログ要件

処理中は適宜ログを出力する。

ログは以下を含む。

- 時刻
- ログレベル
- メッセージ
- コンソール表示時の色

ログレベルは `INFO`、`OK`、`WARN`、`ERROR`、`STEP` とする。

## 15. ✅ 検証要件

インストール中に以下を検証する。

- 各ツールの実体パスが存在すること。
- 各ツールのバージョンコマンドが実行できること。
