# Setup

## Windows Terminal settings.json

Windows Terminal の `settings.json` は通常、次の場所にあります。

```text
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

PowerShell から開く場合は次を実行します。

```powershell
notepad "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
```

`profiles.defaults` に透明化の設定を追加します。既に `defaults` がある場合は中身をマージしてください。

```json
"defaults": {
  "opacity": 85,
  "useAcrylic": true
}
```

`profiles.list` には既存プロファイルを残しつつ、`PowerShell-Portable` と `Cygwin` を追加します。`commandline` の `C:\\Users\\merry\\Desktop\\pdev` は、実際に `setup_v4.ps1` を実行した `-Root` に合わせて変更してください。

```json
"list": [
  {
    "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
    "hidden": false,
    "name": "PowerShell",
    "source": "Windows.Terminal.PowershellCore",
    "tabColor": "#0072C6"
  },
  {
    "guid": "{1f8da638-35da-519c-89e7-669fb6d13432}",
    "hidden": false,
    "name": "Ubuntu",
    "source": "Microsoft.WSL",
    "tabColor": "#77216F"
  },
  {
    "guid": "{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}",
    "hidden": false,
    "name": "Git Bash",
    "source": "Git",
    "tabColor": "#3E2C00"
  },
  {
    "commandline": "%SystemRoot%\\System32\\cmd.exe",
    "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}",
    "name": "Command Prompt",
    "tabColor": "#98971A"
  },
  {
    "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
    "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "name": "Windows PowerShell",
    "tabColor": "#252525"
  },
  {
    "guid": "{b453ae62-4e3d-5e58-b989-0a998ec441b8}",
    "hidden": false,
    "name": "Azure Cloud Shell",
    "source": "Windows.Terminal.Azure",
    "tabColor": "#001E3B"
  },
  {
    "guid": "{bd870082-4113-555a-ba2b-779533e1b847}",
    "hidden": false,
    "name": "Developer Command Prompt for VS 18",
    "source": "Windows.Terminal.VisualStudio"
  },
  {
    "guid": "{c08385c3-fb36-5c57-a25b-f04d1b8c79d0}",
    "hidden": false,
    "name": "Developer PowerShell for VS 18",
    "source": "Windows.Terminal.VisualStudio"
  },
  {
    "commandline": "C:\\Users\\merry\\Desktop\\pdev\\PowerShell.cmd",
    "guid": "{9d1a6c1d-cb79-4ab9-b57d-3dcb9b4efb21}",
    "hidden": false,
    "name": "PowerShell-Portable",
    "startingDirectory": "C:\\Users\\merry\\Desktop\\pdev",
    "tabColor": "#0072C6"
  },
  {
    "commandline": "C:\\Users\\merry\\Desktop\\pdev\\Cygwin.cmd",
    "guid": "{03d6bf4b-5426-4a5e-a6e2-8741d98f2a7d}",
    "hidden": false,
    "name": "Cygwin",
    "startingDirectory": "C:\\Users\\merry\\Desktop\\pdev",
    "tabColor": "#008080"
  }
]
```

`PowerShell-Portable` は Cygwin の PATH を含めません。`Cygwin.cmd` 側も Cygwin の `bin` だけを PATH に入れるため、Rust や cargo のビルド時に Cygwin の `link.exe` が混ざりにくくなります。
