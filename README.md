# pdev-win 検証手順

## 前提

- Windows PowerShell 5.1 以降、または PowerShell 7 以降で実行する。
- 管理者権限は不要。
- `$Root` は必ず `Desktop` 配下を指定する。
- インストール中に各ツールの zip、exe、wheel をネットワークから取得する。
- 日本語を含むパスでも動作するよう、pip のキャッシュパスは `pip.ini` ではなく `PIP_CACHE_DIR` 環境変数で指定する。

## Quick Start

```powershell

```

## 実行例

PowerShell を開き、このリポジトリのディレクトリで実行する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

```powershell
Remove-Item pdev -Recurse -Force ; powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -Root .\pdev
```

```powershell
Remove-Item "pdev_日本語" -Recurse -Force ; powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -Root ".\pdev_日本語"
```

```powershell
Remove-Item "pdev_日本語 空白" -Recurse -Force ; powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -Root ".\pdev_日本語 空白"
```

PowerShell 7 を使う場合:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

## 任意引数の例

ツールのバージョンを指定する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -PythonVersion "3.13.13" `
  -NodeVersion "24.16.0" `
  -UvVersion "0.11.18" `
  -JqVersion "1.8.0" `
  -PandocVersion "3.9.0.2" `
  -VSCodeVersion "stable"
```

Cygwin パッケージを指定する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -CygwinPackages "bash,coreutils,curl,git,openssh,vim,nano"
```

Cygwin mirror はスクリプト内で以下の国内候補から疎通できるものを選択する。

```text
https://ftp.jaist.ac.jp/pub/cygwin/
https://ftp.yamagata-u.ac.jp/pub/cygwin/
https://ftp.iij.ad.jp/pub/cygwin/
```

上記 3 つにアクセスできない場合は、以下にフォールバックする。

```text
https://mirrors.kernel.org/sourceware/cygwin/
```

Cygwin setup は以下の方針で実行する。

- インターネットからインストールする。
- `--no-admin` により現在のユーザのみへインストールする。
- setup の `net-method` を `IE5` に設定し、システムのプロキシ設定を使用する。

既存キャッシュや展開先を上書きして再実行する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -Force
```

## 期待される配置

実行後、`$Root` 配下に以下が作成される。

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
        data/user-data/User/
          settings.json
          extensions.json
      cygwin/
    pkg/
    logs/
    tmp/
  .config/
  VSCode.bat
  Cygwin.bat
```

## 検証 1: 生成物

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"

Test-Path "$Root\.local\opt\python\python.exe"
Test-Path "$Root\.local\opt\nodejs\node.exe"
Test-Path "$Root\.local\opt\uv\uv.exe"
Test-Path "$Root\.local\opt\jq\jq.exe"
Test-Path "$Root\.local\opt\pandoc\pandoc.exe"
Test-Path "$Root\.local\opt\vscode\Code.exe"
Test-Path "$Root\.local\opt\cygwin\bin\bash.exe"
Test-Path "$Root\.local\opt\vscode\data\user-data\User\extensions.json"
Test-Path "$Root\VSCode.bat"
Test-Path "$Root\Cygwin.bat"
```

すべて `True` になることを確認する。

## 検証 2: PATH とバージョン

新しい PowerShell を開き、以下を実行する。

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"
$env:PATH = @(
  "$Root\.local\opt\python",
  "$Root\.local\opt\python\Scripts",
  "$Root\.local\opt\nodejs",
  "$Root\.local\opt\uv",
  "$Root\.local\opt\jq",
  "$Root\.local\opt\pandoc",
  "$Root\.local\opt\vscode\bin",
  "$Root\.local\opt\cygwin\bin",
  $env:PATH
) -join ';'

python --version
pip --version
node --version
npm --version
uv --version
jq --version
pandoc --version
code --version
bash --version
```

各コマンドがエラーなくバージョンを表示することを確認する。

## 検証 3: VS Code 起動

インストール完了後、スクリプトは VS Code を自動起動しない。
最後に表示される起動コマンドを使って手動で起動する。

以下を実行する。

```powershell
& "$env:USERPROFILE\Desktop\pdev\VSCode.bat"
```

確認すること:

- VS Code が起動する。
- 起動後、呼び出し元のコンソールが残り続けない。
- VS Code は `--no-sandbox` と `--disable-gpu` 付きで起動される。

## 検証 4: 推奨拡張

`$Root\.local\opt\vscode\data\user-data\User\extensions.json` には以下の推奨拡張が書き込まれる。

```json
{
  "recommendations": [
    "ZooCodeOrganization.zoo-code",
    "zhuangtongfa.Material-theme"
  ]
}
```

VS Code の Extensions ビューの推奨欄から必要な拡張機能を手動でインストールする。

## 検証 5: VS Code terminal から Cygwin

VS Code 上で Terminal を開き、既定プロファイルまたはプロファイル選択から `Cygwin` を選ぶ。

Terminal で以下を実行する。

```bash
pwd
which bash
bash --version
```

確認すること:

- Cygwin の bash が起動する。
- `which bash` が `$Root/.local/opt/cygwin/bin/bash` 相当を指す。

Root 直下の Cygwin 起動バッチも確認する。

```powershell
& "$env:USERPROFILE\Desktop\pdev\Cygwin.bat"
```

## 検証 6: ログ

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"
Get-ChildItem "$Root\.local\logs" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
```

確認すること:

- `install-*.log` が作成されている。
- エラーがあった場合、どの処理で失敗したか追える。

## 失敗時の確認観点

- `$Root` が `Desktop` 配下になっているか。
- ネットワークから GitHub、Python.org、Node.js、PyPI、Cygwin mirror にアクセスできるか。
- 社内プロキシや証明書設定が必要ではないか。
- `.local/pkg` に壊れたダウンロードキャッシュが残っていないか。
- 再実行時は必要に応じて `-Force` を付ける。
