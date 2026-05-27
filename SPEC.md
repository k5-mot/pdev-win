# Portable Developer Environment for Windows 仕様書

## 1. 目的

管理者権限を持たない Windows 環境でも、開発に必要な主要ツールを利用できるポータブル開発環境を構築する。

本仕様の対象は、ポータブル開発環境を作成する PowerShell スクリプト `Create-Pdev.ps1` と、そのスクリプトによって生成される起動バッチファイルである。

## 2. 基本方針

- インストール、設定、キャッシュ、実行時に作成される関連ファイルは、原則として指定されたインストール先ディレクトリ配下に閉じ込める。
- 管理者権限を要求しない。
- Windows のシステム領域、ユーザーのグローバル環境変数、ユーザープロファイル直下の設定を**絶対に**汚染しない。
- 同一ディレクトリを別の Windows PC に移動しても、可能な範囲で再利用できる構成にする。
- インストールするツールのバージョンは、スクリプト引数で明示的に指定できる。
- ツールの取得とインストールには Scoop などのユーザー権限で利用可能なパッケージマネージャを使用する。

## 3. コーディング規約

### 3.1 コメント

- 複雑な処理を実装する際は、適宜コメントを付与すること。
- 全ての関数は以下のように、関数コメントを付与すること。
  - [関数におけるコメントベースのヘルプの構文](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_comment_based_help?view=powershell-5.1#syntax-for-comment-based-help-in-functions)

```powershell
function Get-Function {
    <#
        .<help keyword>
        <help content>
    #>

# function logic
}
```

### 3.2 出力処理

- Install/Download/Unzip/CacheHit/Error/Info など、ユーザに適宜状況や進捗を伝えるための出力を実施してください。
- ログ出力は、色付きかつ絵文字を活用して、視認性を高めることが望ましいです。

## 4. 対象環境

### 4.1 OS

- Windows 10 以降
- Windows 11

### 4.2 シェル

- Windows PowerShell 5.1 以降

### 4.3 権限

- 管理者権限は不要であること。
- 実行ポリシーによってスクリプト実行が制限される場合は、利用者が次のように一時的に回避できること。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -InstallRoot "C:\path\to\pdev"
```

## 5. 作成物

スクリプト実行後、指定された `InstallRoot` 配下にポータブル開発環境が作成される。

例:

```text
C:\path\to\pdev
|-- .local\
|   |-- scoop\
|   |-- logs\
|   |-- tmp\
|   `-- home\
|-- .cache\
|-- .config\
|   |-- vscode\
|   |   |-- user-data\
|   |   `-- extensions\
|   |-- pip\
|   |-- npm\
|   |-- uv\
|   `-- AppData\
`-- start.bat
```

### 5.1 必須ディレクトリ

| パス | 用途 |
| --- | --- |
| `InstallRoot\.local` | ツール本体、Scoop、ログ、テンポラリ、ポータブル HOME の配置先 |
| `InstallRoot\.local\scoop` | Scoop 本体および Scoop 管理下のツール配置先 |
| `InstallRoot\.local\logs` | インストールログ、検証ログ |
| `InstallRoot\.local\tmp` | インストール時および実行時の一時ファイル |
| `InstallRoot\.local\home` | 起動バッチ内で利用するポータブル HOME |
| `InstallRoot\.cache` | ダウンロードファイル、zipball、Scoop キャッシュ、pip/npm/uv キャッシュなど |
| `InstallRoot\.config` | ツール設定ファイルの配置先 |
| `InstallRoot\.config\vscode\user-data` | VS Code のユーザーデータ |
| `InstallRoot\.config\vscode\extensions` | VS Code 拡張機能 |
| `InstallRoot\.config\pip` | pip 設定ファイル |
| `InstallRoot\.config\npm` | npm 設定ファイル |
| `InstallRoot\.config\uv` | uv 設定ファイル |
| `InstallRoot\.config\AppData` | ポータブル AppData |

## 6. インストール対象ツール

次のツールをインストールする。

| ツール | 既定バージョン | 補足 |
| --- | --- | --- |
| Visual Studio Code | `1.100.2` | 起動時に専用 user-data-dir と extensions-dir を指定する |
| Python | `3.12.10` | `python`、`pip` が利用できること |
| Node.js | `22.16.0` | `node`、`npm` が利用できること |
| uv | `0.7.8` | Python パッケージ管理用 |
| jq | `1.7.1` | JSON 処理用 |
| pandoc | `3.7.0.2` | ドキュメント変換用 |

### 6.1 バージョン指定

インストール対象ツールのバージョンは、引数で上書きできること。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -InstallRoot "C:\path\to\pdev" `
  -PythonVersion 3.12.10 `
  -NodejsVersion 22.16.0 `
  -UvVersion 0.7.8 `
  -JqVersion 1.7.1 `
  -PandocVersion 3.7.0.2 `
  -VscodeVersion 1.100.2
```

指定されたバージョンが取得できない場合は、理由をログに出力し、非ゼロ終了コードで失敗すること。

## 7. スクリプト仕様

### 7.1 ファイル名

- `Create-Pdev.ps1`

### 7.2 文字コード

- `UTF-8 with BOM` で保存すること。

### 7.3 引数

| 引数 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `InstallRoot` | 必須 | なし | ポータブル開発環境の作成先 |
| `PythonVersion` | 任意 | `3.12.10` | インストールする Python のバージョン |
| `NodejsVersion` | 任意 | `22.16.0` | インストールする Node.js のバージョン |
| `UvVersion` | 任意 | `0.7.8` | インストールする uv のバージョン |
| `JqVersion` | 任意 | `1.7.1` | インストールする jq のバージョン |
| `PandocVersion` | 任意 | `3.7.0.2` | インストールする pandoc のバージョン |
| `VscodeVersion` | 任意 | `1.100.2` | インストールする Visual Studio Code のバージョン |
| `StartBatPath` | 任意 | `InstallRoot\start.bat` | 生成する起動バッチファイルのパス |
| `Force` | 任意 | `false` | 既存ファイルがある場合に上書きまたは再インストールを許可する |

### 7.4 実行例

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -InstallRoot "$env:USERPROFILE\Desktop\pdev"
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -InstallRoot "$env:USERPROFILE\Desktop\pdev" `
  -PythonVersion 3.12.10 `
  -NodejsVersion 22.16.0 `
  -StartBatPath "$env:USERPROFILE\Desktop\pdev\start.bat"
```

## 8. インストール処理

### 8.1 事前検証

スクリプトは処理開始時に次を検証する。

- `InstallRoot` が指定されていること。
- `InstallRoot` が作成可能であること。
- `InstallRoot` 配下に必要なディレクトリを作成できること。
- ネットワーク経由で必要なインストール資材を取得できること。
- PowerShell の実行環境が対応バージョンであること。
- 管理者権限がなくても処理を継続できること。

### 8.2 Scoop の配置

Scoop を使用する場合は、Scoop 自体を `InstallRoot\.local\scoop` 配下に配置する。

Scoop 関連の環境変数は、少なくとも次のように `InstallRoot` 配下を向くこと。

| 環境変数 | 値 |
| --- | --- |
| `SCOOP` | `InstallRoot\.local\scoop` |
| `SCOOP_GLOBAL` | 使用しない、または `InstallRoot\.local\scoop-global` |

Scoop のキャッシュ、ダウンロード済みアーカイブは `InstallRoot\.cache` 配下に配置されること。展開済み一時ファイルは `InstallRoot\.local\tmp` 配下に配置されること。

### 8.3 ツールのインストール

各ツールは指定されたバージョンをインストールする。

インストール後、少なくとも次のコマンドが起動バッチ内の PATH から利用できること。

```text
code
python
pip
node
npm
uv
jq
pandoc
```

### 8.4 設定とキャッシュの閉じ込め

起動バッチでは、次のような設定・キャッシュ関連環境変数を `InstallRoot` 配下に向ける。

| 環境変数 | 値 | 用途 |
| --- | --- | --- |
| `HOME` | `InstallRoot\.local\home` | ポータブル HOME |
| `USERPROFILE` | `InstallRoot\.local\home` | 必要に応じてポータブル HOME |
| `APPDATA` | `InstallRoot\.config\AppData\Roaming` | ポータブル Roaming AppData |
| `LOCALAPPDATA` | `InstallRoot\.config\AppData\Local` | ポータブル Local AppData |
| `TEMP` | `InstallRoot\.local\tmp` | ポータブル一時ディレクトリ |
| `TMP` | `InstallRoot\.local\tmp` | ポータブル一時ディレクトリ |
| `PIP_CONFIG_FILE` | `InstallRoot\.config\pip\pip.ini` | pip 設定ファイル |
| `PIP_CACHE_DIR` | `InstallRoot\.cache\pip` | pip キャッシュ |
| `PYTHONUSERBASE` | `InstallRoot\.local\python-userbase` | Python user base |
| `npm_config_cache` | `InstallRoot\.cache\npm` | npm キャッシュ |
| `npm_config_prefix` | `InstallRoot\.local\npm-prefix` | npm グローバル prefix |
| `UV_CACHE_DIR` | `InstallRoot\.cache\uv` | uv キャッシュ |

## 9. 起動バッチ仕様

### 9.1 ファイル名

既定では `InstallRoot\start.bat` を生成する。

互換性のため、必要に応じて `Code.bat` または `Code.cmd` を生成できる設計としてもよい。

### 9.2 起動バッチの責務

起動バッチは次を行う。

1. 自身の配置場所から `InstallRoot` を特定する。
2. `InstallRoot` 配下のツールへ PATH を通す。
3. 設定、キャッシュ、一時ディレクトリ、HOME を `InstallRoot` 配下に向ける。
4. 必須コマンドが `InstallRoot` 配下から解決されているか検証する。
5. 検証結果をコンソールまたはログに出力する。
6. Visual Studio Code を起動する。

### 9.3 PATH 検証

起動バッチは、次のコマンドの解決先を検証する。

```text
code
python
pip
node
npm
uv
jq
pandoc
```

解決先が `InstallRoot` 配下ではない場合は、警告またはエラーとして扱う。

少なくとも `code`、`python`、`node` が `InstallRoot` 配下から解決できない場合は、VS Code を起動せずに失敗すること。

### 9.4 VS Code 起動オプション

VS Code は次の条件で起動する。

- `--user-data-dir` に `InstallRoot\.config\vscode\user-data` を指定する。
- `--extensions-dir` に `InstallRoot\.config\vscode\extensions` を指定する。
- sandbox を無効化する。
- GPU acceleration を無効化する。

起動例:

```bat
code ^
  --user-data-dir "%INSTALL_ROOT%\.config\vscode\user-data" ^
  --extensions-dir "%INSTALL_ROOT%\.config\vscode\extensions" ^
  --no-sandbox ^
  --disable-gpu
```

## 10. ログ仕様

スクリプトは `InstallRoot\.local\logs` 配下にログを出力する。

ログには少なくとも次を含める。

- 実行開始日時
- PowerShell バージョン
- OS 情報
- `InstallRoot`
- 指定されたツールバージョン
- 作成したディレクトリ
- インストールしたツール
- 各ツールの実際のバージョン
- エラー内容
- 実行終了日時

## 11. エラー処理

次の場合は非ゼロ終了コードで失敗する。

- `InstallRoot` が未指定。
- 必要なディレクトリを作成できない。
- Scoop または代替パッケージマネージャの導入に失敗した。
- 指定されたバージョンのツールをインストールできない。
- インストール後のコマンド検証に失敗した。
- 起動バッチを生成できない。

失敗時は、途中まで作成されたファイルを無理に削除しなくてよい。ただし、どの段階で失敗したかをログから追跡できること。

## 12. 冪等性

同じ `InstallRoot` に対して再実行した場合、可能な限り既存のインストールを再利用する。

- 既に同じバージョンがインストール済みの場合は再インストールしない。
- バージョンが異なる場合は、指定されたバージョンへ更新または切り替える。
- `Force` が指定された場合は、必要に応じて再取得、再展開、再生成を行う。
- 起動バッチは、スクリプトの現在仕様に合わせて再生成する。

## 13. 完了条件

スクリプト実行後、次を満たすこと。

- `InstallRoot` 配下に必要なディレクトリが作成されている。
- Scoop または代替パッケージマネージャが `InstallRoot` 配下に配置されている。
- 指定されたバージョンの Visual Studio Code、Python、Node.js、uv、jq、pandoc がインストールされている。
- `start.bat` が生成されている。
- `start.bat` 実行時に PATH と主要環境変数が `InstallRoot` 配下を向く。
- `start.bat` から VS Code が起動できる。
- VS Code の user-data と extensions が `InstallRoot\.config\vscode` 配下に作成される。
- pip、npm、uv の設定が `InstallRoot\.config` 配下に作成される。
- pip、npm、uv などのキャッシュが `InstallRoot\.cache` 配下に作成される。
- インストールログが `InstallRoot\.local\logs` 配下に出力される。

## 14. 非対象

本仕様では次を対象外とする。

- Visual Studio Code 拡張機能の事前インストール。
- Git、Docker、WSL、Visual Studio Build Tools の導入。
- プロキシ認証、社内証明書、オフラインインストールへの完全対応。
- macOS、Linux への対応。
- システム全体の PATH やレジストリへの永続的な変更。
