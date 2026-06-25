# 🧰 pdev: Portable Development Environment for Highly Restricted Windows

`pdev` は、Windows の Desktop 配下にポータブル開発環境を作成する PowerShell スクリプトです。

管理者権限を使わず、Python、Node.js、VS Code、便利な CLI tools を検証済みの `$Root` 配下に配置します。Cygwin は必要な場合だけ `setup_cygwin.ps1` で追加します。既定のインストール先は、OS が解決した Desktop 配下の `pdev` です。

## 🧩 Installed Tools

- Python / pip
- Node.js / npm
- uv
- jq
- pandoc
- bat
- bottom
- crane
- delta
- dust
- eza
- fd
- hyperfine
- procs
- ripgrep
- Visual Studio Code

Python には `setuptools`、`wheel`、`python-docx`、`pypdf`、`Pillow` も追加します。Node.js には npm global package として `npm` と `cowsay` をインストールします。

## ⚡ One-Liner

PowerShell を開き、以下を実行します。

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/k5-mot/pdev-win/refs/heads/main/setup.ps1 | Invoke-Expression
```

または

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/k5-mot/pdev-win/refs/heads/main/setup.ps1))) -Root "$env:USERPROFILE\Desktop\pdev"
```

`setup.ps1` は既定で `[Environment]::GetFolderPath('Desktop')` から解決した `Desktop` 配下の `pdev` を Root にします。

## 🪜 Step-by-Step

スクリプトを確認してから実行したい場合:

```powershell
# 1. リポジトリをクローンする.
git clone https://github.com/k5-mot/pdev-win $env:USERPROFILE\Desktop\pdev-win

# 2. リポジトリの作業ディレクトリへ移動する。
cd "$env:USERPROFILE\Desktop\pdev-win"

# 3. Desktop 配下へ portable environment を作成する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Root "$env:USERPROFILE\Desktop\pdev"
```

既存キャッシュや展開先を上書きする場合は `-Force` を付けます。

```powershell
# 既存のダウンロードキャッシュや展開先を再作成する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev" `
  -Force
```

## 🐚 Optional Cygwin

Cygwin が必要な場合は、基本セットアップ後に追加スクリプトを実行します。

```powershell
# Cygwin を同じ Root 配下へ追加する。
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_cygwin.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
```

`setup_cygwin.ps1` は `$Root\.local\opt\cygwin` を作成し、`$Root\Cygwin.cmd` を生成します。VS Code portable settings が存在する場合は、integrated terminal の `Cygwin` profile も追記します。

## 🚀 Launch

セットアップ完了後、Root 直下のランチャーから起動します。

VS Code:

```powershell
# 1. 既定の Root を組み立てる。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'

# 2. VS Code launcher を起動する。
& "$Root\VSCode.cmd"
```

Optional Cygwin:

```powershell
# 1. 既定の Root を組み立てる。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'

# 2. setup_cygwin.ps1 実行後に Cygwin launcher を起動する。
& "$Root\Cygwin.cmd"
```

Portable PowerShell:

```powershell
# 1. 既定の Root を組み立てる。
$Root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'pdev'

# 2. portable PowerShell launcher を起動する。
& "$Root\PowerShell.cmd"
```

## 📚 Documentation

- 仕様とディレクトリ構成: [docs/SPEC.md](docs/SPEC.md)
- トラブルシューティング: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- コーディング規約: [docs/CODING_RULES.md](docs/CODING_RULES.md)
- image download scripts: [scripts/README.md](scripts/README.md)

## ✅ Local Validation

GitHub Actions workflow の検証には、マシンにインストールした `actionlint` を使います。

```powershell
# 1. actionlint をマシンへインストールする。
winget install --id rhysd.actionlint --exact

# 2. workflow を静的検証する。
actionlint ".github/workflows/validate-portable-dev.yml"
```
