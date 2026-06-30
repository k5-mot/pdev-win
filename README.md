# 🧰 pdev: Portable Development Environment for Highly Restricted Windows

`pdev` は、Windows の Desktop 配下にポータブル開発環境を作成する PowerShell スクリプトです。

管理者権限を使わず、Python、Node.js、VS Code、便利な CLI tools を検証済みの `$Root` 配下に配置します。Cygwin は必要な場合だけ `setup_cygwin.ps1` で追加します。既定のインストール先は、OS が解決した Desktop 配下の `pdev` です。

## 🧩 Installed Tools

- Python
  - pip
- Node.js
  - npm
- uv：Python package/project manager.
- jq：JSON processor.
- pandoc：ドキュメント変換ツール.
- crane：container registry 操作用 CLI. 一部の `docker` / `podman` 操作の代替.
- bat：ファイルビュワー. `cat` 代替.
- bottom：システムモニター. `top` 代替.
- delta：diff ビュワー. `diff` 代替.
- dust：disk usage ビュワー. `du` 代替.
- fd：ファイル検索ツール. `find` 代替.
- hyperfine：コマンド benchmark ツール. `time` 代替.
- ripgrep：テキスト検索ツール. `grep` 代替.
- zoxide：ディレクトリ移動ツール. `cd` 代替.
- lsd：ディレクトリ一覧ツール. `ls` 代替.
- broot：対話的ディレクトリナビゲーター. `tree` 補助.
- xh：HTTP client. `curl` 代替.
- sd：文字列置換ツール. `sed` 代替.
- choose：column/field selector. `cut` 代替.
- genact：fake activity generator.
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

## 🧪 Mise Variant

`setup_mise.ps1` は、mise で toolchain を管理する実験的な代替セットアップです。`mise.exe` 本体は固定バージョンの GitHub Releases asset から取得し、`.config/mise/config.toml` に固定バージョンの tools を書き込みます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_mise.ps1 `
  -Root "$env:USERPROFILE\Desktop\pdev"
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

- トラブルシューティング: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- image download scripts: [scripts/README.md](scripts/README.md)

開発仕様、実装要件、コーディング規約は [openspec/specs](openspec/specs) に集約しています。

## ✅ Local Validation

GitHub Actions workflow の静的検証には、マシンにインストールした `actionlint` を使います。

```powershell
# 1. actionlint をマシンへインストールする。
winget install --id rhysd.actionlint --exact

# 2. workflow を静的検証する。
actionlint ".github/workflows/validate-portable-dev.yml"
actionlint ".github/workflows/check-pinned-versions.yml"
```

固定している GitHub Releases のバージョンが最新かどうかは、CI と同じスクリプトで確認できます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-PinnedGitHubReleaseVersions.ps1
```
