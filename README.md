# pdev-win v2

## Setup

- `Create-Pdev.ps1`は、`UTF-8 with BOM` で保存してください。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -InstallRoot "$env:USERPROFILE\Desktop\pdev-win\pdev"
```

インストール先と各ツールのバージョンを指定できます。
`InstallRoot` の配下に `.local`、`.config`、`start.bat` が作成されます。
Scoop、キャッシュ、HOME、AppData、VS Code の user-data / extensions もこの配下に置かれます。
pip の設定・キャッシュと Python の user base も `InstallRoot` 配下に向けられます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 `
  -InstallRoot "$env:USERPROFILE\Desktop\pdev-win\pdev" `
  -PythonVersion 3.12.10 `
  -NodejsVersion 22.16.0 `
  -UvVersion 0.7.8 `
  -JqVersion 1.7.1 `
  -PandocVersion 3.7.0.2 `
  -VscodeVersion 1.100.2 `
  -StartBatPath "$env:USERPROFILE\Desktop\pdev-win\pdev\start.bat"
```

## Start

```powershell
%USERPROFILE%\Desktop\start.bat
```
