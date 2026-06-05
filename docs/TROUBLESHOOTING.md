# 🛟 Troubleshooting

## 🗂️ Root

- `$Root` が Desktop 配下になっているか確認する。
- Desktop がリダイレクトされている環境では、`[Environment]::GetFolderPath('Desktop')` で解決したパスを使う。
- ネットワーク上のユーザーフォルダーを使う場合は、VPN や認証状態が有効か確認する。

## 🌐 Network

セットアップ中は以下にアクセスできる必要があります。

- GitHub Releases
- Python.org
- Node.js
- PyPI
- VS Code update endpoint
- Cygwin mirror

社内プロキシや証明書設定が必要な場合は、PowerShell から外部 HTTPS にアクセスできる状態にしてから再実行してください。

## 📦 Cache

ダウンロード途中のファイルや壊れたキャッシュが残っている場合は、次を確認します。

```powershell
# Root 配下のダウンロードキャッシュを確認する。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'
Get-ChildItem "$Root\.local\pkg"
```

再取得したい場合は `-Force` を付けて実行します。

```powershell
# キャッシュや展開済みファイルを上書きして再実行する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_v4.ps1 `
  -Root (Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev') `
  -Force
```

## 📝 Logs

ログは `$Root\.local\logs` に作成されます。

```powershell
# 最新の install log を確認する。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'
Get-ChildItem "$Root\.local\logs" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3
```

Cygwin/VS Code extensions/pip packages/npm packages など、出力が多い処理はコンソールではなくログファイルに記録されます。

## 🚀 Launchers

Root 直下に以下があるか確認します。

```powershell
# Root 直下の launcher が生成されているか確認する。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'
Test-Path "$Root\VSCode.cmd"
Test-Path "$Root\Cygwin.cmd"
Test-Path "$Root\PowerShell.cmd"
```

ネットワークパス上の Root では、ランチャーが `pushd` で作業ディレクトリを確立してから起動します。起動できない場合は、Root へアクセスできる状態か確認してください。

## 🧩 VS Code Extensions

拡張機能の状態を確認する場合:

```powershell
# portable extensions dir に入っている VS Code extensions を確認する。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'
& "$Root\.local\opt\vscode\bin\code.cmd" `
  --user-data-dir "$Root\.local\opt\vscode\data\user-data" `
  --extensions-dir "$Root\.local\opt\vscode\data\extensions" `
  --list-extensions
```

## 🐚 Cygwin

Cygwin が起動するか確認します。

```powershell
# Root 直下の Cygwin launcher を起動する。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'
& "$Root\Cygwin.cmd"
```

Cygwin 側では `which bash` が `$Root/.local/opt/cygwin/bin/bash` 相当を指すことを確認します。
