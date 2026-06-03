# Testing

セットアップ後の検証手順です。`$Root` は実際に指定したインストール先に合わせて変更してください。

## 1. 生成物

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"

Test-Path "$Root\.local\opt\python\python.exe"
Test-Path "$Root\.local\opt\nodejs\node.exe"
Test-Path "$Root\.local\opt\uv\uv.exe"
Test-Path "$Root\.local\opt\jq\jq.exe"
Test-Path "$Root\.local\opt\pandoc\pandoc.exe"
Test-Path "$Root\.local\opt\vscode\Code.exe"
Test-Path "$Root\.local\opt\cygwin\bin\bash.exe"
Test-Path "$Root\.local\opt\vscode\data\user-data\User\settings.json"
Test-Path "$Root\.local\opt\vscode\data\user-data\User\extensions.json"
Test-Path "$Root\.local\opt\vscode\data\extensions"
Test-Path "$Root\.config\pip\pip.ini"
Test-Path "$Root\VSCode.bat"
Test-Path "$Root\Cygwin.bat"
```

すべて `True` になることを確認します。

## 2. PATH とバージョン

新しい PowerShell を開き、以下を実行します。

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

各コマンドがエラーなくバージョンを表示することを確認します。

## 3. VS Code

インストール完了後、VS Code は自動起動しません。以下で手動起動します。

```powershell
& "$env:USERPROFILE\Desktop\pdev\VSCode.bat"
```

確認すること:

- VS Code が起動する。
- 起動後、呼び出し元のコンソールが残り続けない。
- VS Code は `--no-sandbox` と `--disable-gpu` 付きで起動される。
- portable mode の `user-data` と `extensions` が使われる。

## 4. VS Code Terminal から Cygwin

VS Code 上で Terminal を開き、既定プロファイルまたはプロファイル選択から `Cygwin` を選びます。

```bash
pwd
which bash
bash --version
```

確認すること:

- Cygwin の bash が起動する。
- `which bash` が `$Root/.local/opt/cygwin/bin/bash` 相当を指す。

Root 直下の Cygwin 起動バッチも確認します。

```powershell
& "$env:USERPROFILE\Desktop\pdev\Cygwin.bat"
```

## 5. VS Code Extensions

以下の拡張機能が portable extensions dir にインストールされていることを確認します。

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"
& "$Root\.local\opt\vscode\bin\code.cmd" `
  --user-data-dir "$Root\.local\opt\vscode\data\user-data" `
  --extensions-dir "$Root\.local\opt\vscode\data\extensions" `
  --list-extensions
```

確認対象:

- `ZooCodeOrganization.zoo-code`
- `zhuangtongfa.Material-theme`
- `openai.chatgpt`
- `anthropic.claude-code`

## 6. ログ

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"
Get-ChildItem "$Root\.local\logs" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3
```

確認すること:

- `install-*.log` が作成されている。
- エラーがあった場合、どの処理で失敗したか追える。
