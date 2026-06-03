# 手動検証手順

この手順は `Create-Pdev_v2.ps1` を対象にします。
検証用の `InstallRoot` は既存環境と混ざらないように、リポジトリ直下の `.verify-pdev-v2` を例にしています。

## 1. 構文チェック

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\Create-Pdev_v2.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null

if ($errors) {
  $errors | Format-List *
} else {
  "Parse OK"
}
```

## 2. UTF-8 BOM チェック

```powershell
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path .\Create-Pdev_v2.ps1))
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  "UTF-8 BOM OK"
} else {
  "UTF-8 BOM NG"
}
```

## 3. セットアップ実行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev_v2.ps1 `
  -InstallRoot "$PWD\.verify-pdev-v2"
```

終了コードを確認します。

```powershell
$LASTEXITCODE
```

`0` なら成功です。失敗した場合はログを確認します。

```powershell
Get-ChildItem .\.verify-pdev-v2\.local\logs
Get-Content .\.verify-pdev-v2\.local\logs\create-pdev-v2-*.log -Tail 120
```

## 4. 生成物チェック

```powershell
$root = Resolve-Path .\.verify-pdev-v2
@(
  ".local\scoop",
  ".local\logs",
  ".local\tmp",
  ".local\home",
  ".cache",
  ".cache\powershell",
  ".config\vscode\user-data",
  ".config\vscode\extensions",
  ".config\pip\pip.ini",
  ".config\npm\npmrc",
  ".config\uv\uv.toml",
  "start.bat"
) | ForEach-Object {
  $path = Join-Path $root $_
  [pscustomobject]@{ Path = $path; Exists = Test-Path $path }
}
```

すべて `Exists = True` になることを確認します。

## 5. PowerShell ModuleAnalysisCache の閉じ込め確認

`InstallRoot` 外に `Microsoft\Windows\PowerShell\ModuleAnalysisCache` が作られていないことを確認します。

```powershell
Test-Path .\Microsoft\Windows\PowerShell\ModuleAnalysisCache
```

新規検証前に存在しなかった環境では `False` になることが期待値です。

`InstallRoot` 側には PowerShell 用キャッシュディレクトリが作られます。

```powershell
Test-Path .\.verify-pdev-v2\.cache\powershell
Select-String -Path .\.verify-pdev-v2\start.bat -Pattern "PSModuleAnalysisCachePath"
Select-String -Path .\.verify-pdev-v2\.local\logs\create-pdev-v2-*.log -Pattern "ModuleAnalysisCache"
```

## 6. コーディング規約チェック

すべての関数にコメントベースヘルプがあるか確認します。

```powershell
$script = Get-Content -Raw .\Create-Pdev_v2.ps1
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
$functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

$functions | ForEach-Object {
  [pscustomobject]@{
    Function = $_.Name
    HasCommentHelp = [bool]$_.GetHelpContent()
  }
}
```

すべて `HasCommentHelp = True` になることを確認します。

ログ出力の色付き表示と prefix は、セットアップ実行時のコンソール出力で確認します。

## 7. コマンド解決と VS Code 起動確認

```powershell
& "$PWD\.verify-pdev-v2\start.bat"
```

`code`、`python`、`pip`、`node`、`npm`、`uv`、`jq`、`pandoc` の解決先が `.verify-pdev-v2` 配下として表示されることを確認します。
少なくとも `code`、`python`、`node` が `InstallRoot` 配下から解決できない場合、`start.bat` は VS Code を起動せずに失敗します。

## 8. バージョン確認

セットアップログに各ツールのバージョン出力が残っていることを確認します。

```powershell
Select-String -Path .\.verify-pdev-v2\.local\logs\create-pdev-v2-*.log `
  -Pattern "VS Code version output","Python version output","Node.js version output","uv version output","jq version output","pandoc version output","pip version output"
```
