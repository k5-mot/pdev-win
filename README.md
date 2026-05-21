# Portable Development Environment for Windows

Windows 上に、管理者権限なしで使えるポータブル開発環境を作成するためのセットアップスクリプトです。

## 含まれるツール

- Python embeddable package
- Node.js
- uv
- jq
- pandoc
- Visual Studio Code Portable
- VSCode 拡張機能一式

## ディレクトリ構成

```text
.
├─ .local\opt\      # python / node / uv / jq / pandoc / vscode の実体
├─ .cache\          # pip / uv / npm のキャッシュ
├─ .tmp\            # zipball、exe、get-pip.py、拡張機能インストールログなどの一時ファイル
├─ start-pdev.cmd   # ポータブル PATH で VSCode を起動
└─ verify-pdev.cmd  # 各ツールの疎通確認
```

## セットアップ

`pwsh.exe` ではなく Windows PowerShell の `powershell.exe` で実行してください。

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Create-PortableDev.ps1
```

既存の一時ファイルや導入済みツールを作り直す場合:

```powershell
Remove-Item .local, .tmp -Recurse -Force
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

または VSCode のターミナルで個別に確認します。

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
ms-vscode-remote.vscode-remote-extensionpack
ms-vscode-remote.remote-wsl
ms-vscode-remote.remote-containers
ms-vscode-remote.remote-ssh
ms-vscode-remote.remote-ssh-edit
ms-vscode.remote-server
ms-vscode.remote-explorer
zhuangtongfa.material-theme
pkief.material-icon-theme
hediet.vscode-drawio
rooveterinaryinc.roo-cline
zoocodeorganization.zoo-code
saoudrizwan.claude-dev
continue.continue
shd101wyy.markdown-preview-enhanced
yzhang.markdown-all-in-one
bierner.markdown-mermaid
```

拡張機能のインストールログは `.tmp\vscode-extension-install.log` に出力されます。

## 参考資料

- [Python](https://www.python.org/downloads/windows/)
- [Node.js](https://nodejs.org/ja/download)
- [uv](https://github.com/astral-sh/uv)
- [jq](https://github.com/jqlang/jq)
- [pandoc](https://github.com/jgm/pandoc)
- [Visual Studio Code](https://code.visualstudio.com/download)
  - [Updates](https://code.visualstudio.com/updates)
