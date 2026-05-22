# Portable Development Environment for Windows

Windows 上に、管理者権限なしで使えるポータブル開発環境を作成するためのセットアップスクリプトです。
また、ユーザディレクトリ以下の"Desktop"や"Downloads"にすべてのファイルを置いて使うことを想定しています。

## 含まれるツール

- Visual Studio Code Portable
- VSCode 拡張機能一式
- Python embeddable package
- pip
- Node.js
- uv
- jq
- pandoc

## ディレクトリ構成

```text
.
├─ .local\opt\      # python / node / uv / jq / pandoc / vscode の実体
├─ .local\pkgs\     # zipball、exe、wheel、tgz などの取得物
├─ .local\tmp\      # 展開用ディレクトリ、ログ、作業用の一時ファイル
├─ .local\home\     # 子プロセス用の USERPROFILE / HOME / AppData
├─ .config\npm\     # npm のポータブル設定ファイル
├─ .cache\          # pip / uv / npm のキャッシュ
├─ start-pdev.cmd   # ポータブル PATH で VSCode を起動
└─ verify-pdev.cmd  # 各ツールの疎通確認
```

## セットアップ

`pwsh.exe` ではなく Windows PowerShell の `powershell.exe` で実行してください。
このリポジトリは `%USERPROFILE%\Desktop` または `%USERPROFILE%\Downloads` 配下に置いてください。
それ以外の場所では `Create-PortableDev.ps1` が停止します。

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Create-PortableDev.ps1
```

既存の一時ファイルや導入済みツールを作り直す場合:

```powershell
Remove-Item .cache, .config, .local -Recurse -Force
.\Create-PortableDev.ps1 -Force
```

`.cache` には pip / uv / npm のキャッシュが入るため、通常は削除不要です。

## 起動

```cmd
start-pdev.cmd
```

VSCode は `.local\opt\vscode\Code.exe` から起動します。VSCode Portable Mode のデータは以下に保存されます。

```text
.local\opt\vscode\data\user-data
.local\opt\vscode\data\extensions
```

## 検証

```cmd
verify-pdev.cmd
```

`Create-PortableDev.ps1` は `start-pdev.cmd` と `verify-pdev.cmd` を作成した後、以下と同等の動作確認も実行します。
動作確認の詳細ログは `.local\tmp\verify-pdev.log` に出力されます。
VSCode のターミナルで個別に確認する場合も同じ内容を使えます。

```powershell
Write-Host @"
Python : $(python --version)
pip    : $(pip --version)
Node.js: $(node --version)
npm    : $(npm --version)
uv     : $(uv --version)
jq     : $(jq --version)
pandoc : $(pandoc --version)
"@

(Get-Command python).Source
(Get-Command pip).Source
(Get-Command node).Source
(Get-Command npm).Source
(Get-Command uv).Source
(Get-Command jq).Source
(Get-Command pandoc).Source
(Get-Command code).Source
```

## バージョン指定

既定では指定系列の最新バージョンを取得します。固定したい場合はパラメーターを指定します。

```powershell
.\Create-PortableDev.ps1 `
  -PythonVersion 3.14.5 `
  -NodeVersion 24.16.0 `
  -UvVersion 0.11.15 `
  -JqVersion jq-1.8.1 `
  -PandocVersion 3.9.0.2 `
  -VsCodeVersion 1.121.0
```

## VSCode 設定

`Create-PortableDev.ps1` は以下の設定ファイルを作成します。

```text
.local\opt\vscode\data\argv.json
.local\opt\vscode\data\user-data\User\settings.json
```

統合ターミナルの既定プロファイルは Windows PowerShell に設定されます。

## 事前インストールされる VSCode 拡張機能

```text
zhuangtongfa.material-theme
pkief.material-icon-theme
hediet.vscode-drawio
rooveterinaryinc.roo-cline
zoocodeorganization.zoo-code
shd101wyy.markdown-preview-enhanced
bierner.markdown-mermaid
```

拡張機能のインストールログは `.local\tmp\vscode-extension-install.log` に出力されます。

## 使い方

```powershell
### pip
mkdir -Force "$env:PDEV_ROOT\.local\tmp\pip" ; cd "$env:PDEV_ROOT\.local\tmp\pip"
mkdir -Force "$env:PDEV_ROOT\.local\pkgs\pip"
pip download -d "$env:PDEV_ROOT\.local\pkgs\pip" pyfiglet
pip install --find-links="$env:PDEV_ROOT\.local\pkgs\pip" pyfiglet
pip list
pyfiglet "portable pip works"

### npm
mkdir -Force "$env:PDEV_ROOT\.local\tmp\npm" ; cd "$env:PDEV_ROOT\.local\tmp\npm"
mkdir -Force "$env:PDEV_ROOT\.local\pkgs\npm"
npm pack cowsay --pack-destination "$env:PDEV_ROOT\.local\pkgs\npm"
npm -g i (Get-ChildItem "$env:PDEV_ROOT\.local\pkgs\npm\cowsay-*.tgz" | Select-Object -First 1).FullName
npm -g list --depth=0
cowsay "portable npm works"

### uv
mkdir -Force "$env:PDEV_ROOT\.local\tmp\uv" ; cd "$env:PDEV_ROOT\.local\tmp\uv"
mkdir -Force "$env:PDEV_ROOT\.local\pkgs\pip"
uv init
uv venv
pip download -d "$env:PDEV_ROOT\.local\pkgs\pip" catsay-cli
uv add --dev --find-links="$env:PDEV_ROOT\.local\pkgs\pip" catsay-cli
uv pip list
uv run catsay "portable uv works"

### jq
echo '{ "name": "Alice", "age": 25 }' | jq

### pandoc
mkdir -Force "$env:PDEV_ROOT\.local\tmp\pandoc" ; cd "$env:PDEV_ROOT\.local\tmp\pandoc"
pandoc "$env:PDEV_ROOT\README.md" -o README.html
```

## 参考資料

- [Visual Studio Code](https://code.visualstudio.com/download)
  - [Updates](https://code.visualstudio.com/updates)
- [Python](https://www.python.org/downloads/windows/)
- [Node.js](https://nodejs.org/ja/download)
- [uv](https://github.com/astral-sh/uv)
- [jq](https://github.com/jqlang/jq)
- [pandoc](https://github.com/jgm/pandoc)
