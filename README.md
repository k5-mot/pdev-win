# pdev-win v2

Windows 10/11 上に、管理者権限なしで使えるポータブル開発環境を作成します。
ツール本体、設定、キャッシュ、一時ファイル、VS Code の user-data / extensions は、指定した `InstallRoot` 配下に配置されます。

## 作成される主な構成

```text
pdev
|-- .local\
|   |-- scoop\
|   |-- logs\
|   |-- tmp\
|   `-- home\
|-- .cache\
|-- .config\
|   |-- vscode\
|   |   |-- user-data\
|   |   `-- extensions\
|   |-- pip\
|   |-- npm\
|   |-- uv\
|   `-- AppData\
`-- start.bat
```

## セットアップ

`Create-Pdev.ps1` は `UTF-8 with BOM` で保存されています。
実行ポリシーで止まる環境では、次のように一時的に bypass して実行してください。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -InstallRoot "$env:USERPROFILE\Desktop\pdev"
```

各ツールのバージョンと `start.bat` の生成先も指定できます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -InstallRoot "$env:USERPROFILE\Desktop\pdev" `
  -PythonVersion 3.12.10 `
  -NodejsVersion 22.16.0 `
  -UvVersion 0.7.8 `
  -JqVersion 1.7.1 `
  -PandocVersion 3.7.0.2 `
  -VscodeVersion 1.121.0 `
  -AdditionalTools ripgrep,fd,bat,delta,curl,lazygit,neovim,yq,hyperfine,rustup `
  -StartBatPath "$env:USERPROFILE\Desktop\pdev\start.bat"
```

既存の環境を再利用しつつ、必要に応じて再取得や再生成を許可する場合は `-Force` を付けます。

## インストール対象

| ツール | 既定バージョン |
| --- | --- |
| Visual Studio Code | `1.121.0` |
| Python | `3.12.10` |
| Node.js | `22.16.0` |
| uv | `0.7.8` |
| jq | `1.7.1` |
| pandoc | `3.7.0.2` |

追加で次の Scoop ツールも最新 manifest からインストールします。

```text
ripgrep
fd
bat
delta
curl
lazygit
neovim
yq
hyperfine
rustup
```

## 起動

セットアップ後、生成されたバッチファイルを実行します。

```powershell
& "$env:USERPROFILE\Desktop\pdev\start.bat"
```

`start.bat` は `HOME`、`USERPROFILE`、`APPDATA`、`LOCALAPPDATA`、`TEMP`、`TMP`、pip/npm/uv の設定・キャッシュ関連環境変数を `InstallRoot` 配下に向け、`code`、`python`、`node` などが同じ `InstallRoot` 配下から解決されることを確認してから VS Code を起動します。

## ログ

セットアップログは次に出力されます。

```text
<InstallRoot>\.local\logs\create-pdev-YYYYMMDD-HHMMSS.log
```

指定バージョンが取得できない場合や、インストール後の検証に失敗した場合は、非ゼロ終了コードで終了します。
