# pdev-win

`pdev-win` は、Windows の `Desktop` 配下だけを使ってポータブル開発環境を構築する PowerShell スクリプトです。

管理者権限なしで、Python / pip / Node.js / uv / jq / pandoc / VS Code / Cygwin を `$Root` 配下に配置します。インストール後は VS Code と Cygwin の起動バッチも生成されます。

## Quick Start

PowerShell を開き、以下を実行します。

```powershell
iwr https://raw.githubusercontent.com/k5-mot/pdev-win/main/setup.ps1 | iex
```

既定のインストール先は `$env:USERPROFILE\Desktop\pdev` です。

## Targets

- Windows PowerShell 5+。
- 管理者権限なし。
- インストール先は `Desktop` 配下。
- ネットワークから各ツールの zip、exe、wheel を取得できる環境。

## Documentation

- セットアップ手順: [docs/USAGE.md](docs/USAGE.md)
- 検証手順: [docs/TESTING.md](docs/TESTING.md)
- 仕様: [docs/SPEC.md](docs/SPEC.md)

## Installed Tools

- Python / pip
- Node.js / npm
- uv
- jq
- pandoc
- Visual Studio Code
- Cygwin

## Output

既定では以下に環境を作成します。

```text
%USERPROFILE%\Desktop\pdev\
  .local\
  .config\
  VSCode.bat
  Cygwin.bat
```

セットアップ完了後は、`VSCode.bat` または `Cygwin.bat` から起動します。

## Coding Agent Setup

コーディングエージェント用の設定を使う場合は、セットアップ後に以下を実行します。

```powershell
$Root = "$env:USERPROFILE\Desktop\pdev"

New-Item -ItemType Directory -Force -Path "$Root\.claude" | Out-Null
Copy-Item -Force ".\.claude\settings.json" "$Root\.claude\settings.json"

New-Item -ItemType Directory -Force -Path "$Root\.config\codex" | Out-Null
Copy-Item -Force ".\.codex\config.toml" "$Root\.config\codex\config.toml"
```

`$Root` を変更してセットアップした場合は、実際のインストール先に合わせて変更してください。
