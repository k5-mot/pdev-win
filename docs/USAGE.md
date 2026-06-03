# Usage

`setup.ps1` は、指定した `$Root` 配下にポータブル開発環境を作成します。

## Quick Start

PowerShell を開き、以下を実行します。

```powershell
iwr https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup.ps1 | iex
```

既定では `$env:USERPROFILE\Desktop\pdev` にインストールされます。

## Step-by-Step Start

スクリプトを確認してから実行したい場合は、以下の手順で進めます。

```powershell
# 0. TLS 1.2 を有効にする。
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. 作業ディレクトリへ移動する。
mkdir "$env:USERPROFILE\Desktop\pdev-win" -Force
cd "$env:USERPROFILE\Desktop\pdev-win"

# 2. setup.ps1 をダウンロードする。
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup.ps1" `
  -OutFile setup.ps1 `
  -UseBasicParsing

# 3. セットアップスクリプトを実行する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

`-Root` を指定する場合は、必ず `Desktop` 配下のパスにしてください。

## One-Liner

Windows Terminal や cmd.exe などから Windows PowerShell を明示して実行する場合:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup.ps1'))"
```

配置先を指定する場合:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup.ps1"))) -Root "$env:USERPROFILE\Desktop\pdev"
```

## Local Run

このリポジトリを clone 済みの場合は、リポジトリ直下で実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

PowerShell 7 を使う場合:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

## Options

ツールのバージョンを指定する例:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -PythonVersion "3.12.10" `
  -NodeVersion "24.16.0" `
  -UvVersion "0.11.18" `
  -JqVersion "1.8.0" `
  -PandocVersion "3.9.0.2" `
  -VSCodeVersion "stable"
```

Cygwin パッケージを指定する例:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -CygwinPackages "bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux"
```

既存キャッシュや展開先を上書きして再実行する例:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -Force
```

## Installed Layout

実行後、`$Root` 配下に以下が作成されます。

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
    logs/
    tmp/
  .config/
    pip/
      pip.ini
  VSCode.bat
  Cygwin.bat
```

## Installed Tools

既定では以下を導入します。

| Tool | Default |
| --- | --- |
| Python | `3.12.10` |
| Node.js | `24.16.0` |
| uv | `0.11.18` |
| jq | `1.8.0` |
| pandoc | `3.9.0.2` |
| VS Code | `stable` |
| Cygwin | setup 実行時点の最新パッケージ |

VS Code には以下の拡張機能を portable extensions dir へインストールし、推奨拡張にも書き込みます。

- `ZooCodeOrganization.zoo-code`
- `zhuangtongfa.Material-theme`
- `openai.chatgpt`
- `anthropic.claude-code`

## Cygwin Mirror

Cygwin mirror は以下の国内候補から疎通できるものを選択します。

```text
https://ftp.jaist.ac.jp/pub/cygwin/
https://ftp.yamagata-u.ac.jp/pub/cygwin/
https://ftp.iij.ad.jp/pub/cygwin/
```

上記にアクセスできない場合は、以下にフォールバックします。

```text
https://mirrors.kernel.org/sourceware/cygwin/
```

Cygwin setup は以下の方針で実行します。

- インターネットからインストールする。
- `--no-admin` により現在のユーザーのみにインストールする。
- setup の `net-method` を `IE5` に設定し、システムのプロキシ設定を使う。

## Launch

VS Code:

```powershell
& "$env:USERPROFILE\Desktop\pdev\VSCode.bat"
```

Cygwin:

```powershell
& "$env:USERPROFILE\Desktop\pdev\Cygwin.bat"
```

## Troubleshooting

- `$Root` が `Desktop` 配下になっているか確認する。
- GitHub、Python.org、Node.js、PyPI、Cygwin mirror にアクセスできるか確認する。
- 社内プロキシや証明書設定が必要ではないか確認する。
- `.local/pkg` に壊れたダウンロードキャッシュが残っていないか確認する。
- 再実行時は必要に応じて `-Force` を付ける。
