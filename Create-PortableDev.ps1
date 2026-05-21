param(
    # 取得する Python のマイナーバージョン。未指定ならこの系列の最新リリースを探す。
    [string]$PythonMinor = "3.14",
    # 取得する Node.js のメジャーバージョン。未指定ならこの系列の最新リリースを探す。
    [string]$NodeMajor = "24",
    # 固定バージョンを使いたい場合だけ指定する。
    [string]$PythonVersion = "",
    [string]$NodeVersion = "",
    [string]$UvVersion = "",
    [string]$JqVersion = "",
    [string]$PandocVersion = "",
    [string]$VsCodeVersion = "",
    [ValidateSet("x64")]
    [string]$Arch = "x64",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CacheDir = Join-Path $Root ".cache"
$TmpDir = Join-Path $Root ".tmp"
$LocalDir = Join-Path $Root ".local"
$OptDir = Join-Path $LocalDir "opt"
$PythonDir = Join-Path $OptDir "python"
$NodeDir = Join-Path $OptDir "node"
$UvDir = Join-Path $OptDir "uv"
$JqDir = Join-Path $OptDir "jq"
$PandocDir = Join-Path $OptDir "pandoc"
$VsCodeDir = Join-Path $OptDir "vscode"

$VsCodeExtensions = @(
    # VSCode Remote Development
    "ms-vscode-remote.vscode-remote-extensionpack",
    "ms-vscode-remote.remote-wsl",
    "ms-vscode-remote.remote-containers",
    "ms-vscode-remote.remote-ssh",
    "ms-vscode-remote.remote-ssh-edit",
    "ms-vscode.remote-server",
    "ms-vscode.remote-explorer",
    # カラーテーマ
    "zhuangtongfa.material-theme",
    "pkief.material-icon-theme",
    # Draw.io
    "hediet.vscode-drawio",
    # コーディングエージェント
    "rooveterinaryinc.roo-cline",
    "zoocodeorganization.zoo-code",
    "saoudrizwan.claude-dev",
    "continue.continue",
    # Markdown
    "shd101wyy.markdown-preview-enhanced",
    "yzhang.markdown-all-in-one",
    "bierner.markdown-mermaid"
)

<#
.SYNOPSIS
指定したディレクトリを作成します。

.DESCRIPTION
指定パスが存在しない場合だけディレクトリを作成します。既に存在する場合は何もしません。

.PARAMETER Path
作成するディレクトリのパス。
#>
function New-Dir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

<#
.SYNOPSIS
ディレクトリの中身を削除します。

.DESCRIPTION
再インストール時に古い展開内容が混ざらないよう、指定ディレクトリ配下のファイルとサブディレクトリを削除します。
指定ディレクトリが存在しない場合は作成します。

.PARAMETER Path
中身を空にするディレクトリのパス。
#>
function Remove-DirContents {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Force | Remove-Item -Recurse -Force
    } else {
        New-Dir $Path
    }
}

<#
.SYNOPSIS
JSON API を呼び出します。

.DESCRIPTION
GitHub Releases API や Node.js の配布一覧 API を、共通の User-Agent 付きで取得します。

.PARAMETER Uri
取得する JSON API の URL。
#>
function Invoke-Json {
    param([Parameter(Mandatory)][string]$Uri)
    Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "portable-dev-bootstrap" }
}

<#
.SYNOPSIS
ファイルをダウンロードします。

.DESCRIPTION
既存ファイルがあり Force が指定されていない場合は再利用します。
zipball やインストーラーなどの一時成果物は .tmp 配下のパスを渡して保存します。

.PARAMETER Uri
ダウンロード元 URL。

.PARAMETER OutFile
保存先ファイルパス。
#>
function Save-File {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    if ((Test-Path -LiteralPath $OutFile) -and -not $Force) {
        Write-Host "📦 Using existing: $OutFile"
        return
    }

    Write-Host "⬇️  Downloading: $Uri"
    New-Dir (Split-Path -Parent $OutFile)
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers @{ "User-Agent" = "portable-dev-bootstrap" }
}

<#
.SYNOPSIS
zip ファイルをクリーンなディレクトリへ展開します。

.DESCRIPTION
zip を一時ディレクトリへ展開してから、配置先ディレクトリを空にしてコピーします。
zip の最上位に単一ディレクトリだけがある形式では、必要に応じてその階層を取り除けます。

.PARAMETER ZipPath
展開する zip ファイルのパス。

.PARAMETER Destination
展開後の配置先ディレクトリ。

.PARAMETER StripSingleTopDirectory
zip 内の最上位が単一ディレクトリの場合、その中身を配置先へコピーします。
#>
function Expand-ZipToCleanDir {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$StripSingleTopDirectory
    )

    $Temp = Join-Path $env:TEMP ("pdev-" + [guid]::NewGuid().ToString("N"))
    New-Dir $Temp
    Write-Host "📂 Expanding: $ZipPath"
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Temp -Force
        Remove-DirContents $Destination

        $Source = $Temp
        if ($StripSingleTopDirectory) {
            $Items = @(Get-ChildItem -LiteralPath $Temp -Force)
            if ($Items.Count -eq 1 -and $Items[0].PSIsContainer) {
                $Source = $Items[0].FullName
            }
        }

        Get-ChildItem -LiteralPath $Source -Force |
            Copy-Item -Destination $Destination -Recurse -Force
    } finally {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
Python の最新パッチバージョンを取得します。

.DESCRIPTION
python.org の配布一覧から、指定されたマイナー系列に一致する最新バージョンを解決します。

.PARAMETER Minor
検索する Python のマイナー系列。例: 3.14。
#>
function Get-LatestPythonVersion {
    param([Parameter(Mandatory)][string]$Minor)

    $Html = Invoke-WebRequest -Uri "https://www.python.org/ftp/python/" -UseBasicParsing
    $Pattern = [regex]::Escape($Minor) + "\.\d+/"
    $Versions = [regex]::Matches($Html.Content, $Pattern) |
        ForEach-Object { $_.Value.TrimEnd("/") } |
        Sort-Object { [version]$_ } -Descending

    if (-not $Versions) {
        throw "Could not find a Python $Minor release on python.org."
    }
    $Versions[0]
}

<#
.SYNOPSIS
Node.js の最新パッチバージョンを取得します。

.DESCRIPTION
Node.js の配布一覧から、指定メジャー系列かつ Windows x64 zip が提供されている最新バージョンを解決します。

.PARAMETER Major
検索する Node.js のメジャー系列。例: 24。
#>
function Get-LatestNodeVersion {
    param([Parameter(Mandatory)][string]$Major)

    $Releases = Invoke-Json "https://nodejs.org/dist/index.json"
    $Versions = $Releases |
        Where-Object { $_.version -match "^v$Major\." -and $_.files -contains "win-x64-zip" } |
        ForEach-Object { $_.version.TrimStart("v") } |
        Sort-Object { [version]$_ } -Descending

    if (-not $Versions) {
        throw "Could not find a Node.js $Major release with win-x64 zip."
    }
    $Versions[0]
}

<#
.SYNOPSIS
GitHub Releases の latest タグを取得します。

.DESCRIPTION
指定した GitHub リポジトリの latest release から tag_name を取得します。

.PARAMETER Repo
owner/name 形式の GitHub リポジトリ名。
#>
function Get-LatestGitHubTag {
    param([Parameter(Mandatory)][string]$Repo)
    (Invoke-Json "https://api.github.com/repos/$Repo/releases/latest").tag_name
}

<#
.SYNOPSIS
ポータブル Python をインストールします。

.DESCRIPTION
Python embeddable package を .local\opt\python に展開し、site の有効化と pip の導入を行います。
pip のキャッシュは .cache\pip に固定します。
#>
function Install-Python {
    if (-not $PythonVersion) {
        $script:PythonVersion = Get-LatestPythonVersion $PythonMinor
    }

    $ZipName = "python-$PythonVersion-embed-amd64.zip"
    $ZipPath = Join-Path $TmpDir $ZipName
    $Url = "https://www.python.org/ftp/python/$PythonVersion/$ZipName"

    Save-File $Url $ZipPath
    Expand-ZipToCleanDir $ZipPath $PythonDir

    # Embeddable Python は既定で site を読み込まないため、pip が使えるように有効化する。
    $Pth = Get-ChildItem -LiteralPath $PythonDir -Filter "python*._pth" | Select-Object -First 1
    if ($Pth) {
        $Text = Get-Content -LiteralPath $Pth.FullName -Raw
        $Text = $Text -replace "#import site", "import site"
        if ($Text -notmatch "(?m)^Lib\\site-packages$") {
            $Text = $Text.TrimEnd() + "`r`nLib\site-packages`r`n"
        }
        Set-Content -LiteralPath $Pth.FullName -Value $Text -Encoding ASCII
    }

    $GetPip = Join-Path $TmpDir "get-pip.py"
    Save-File "https://bootstrap.pypa.io/get-pip.py" $GetPip

    # ユーザー環境の site-packages を見ないようにして、ポータブル環境へ pip を入れる。
    $Env:PYTHONNOUSERSITE = "1"
    $Env:PIP_CACHE_DIR = Join-Path $CacheDir "pip"
    $Env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
    Write-Host "🐍 Installing Python $PythonMinor..." -ForegroundColor Gray
    & (Join-Path $PythonDir "python.exe") $GetPip --no-warn-script-location
}

<#
.SYNOPSIS
ポータブル Node.js をインストールします。

.DESCRIPTION
Node.js の Windows x64 zip を .local\opt\node に展開します。
npm のグローバルインストール先とキャッシュ先もポータブル環境配下に作成します。
#>
function Install-Node {
    if (-not $NodeVersion) {
        $script:NodeVersion = Get-LatestNodeVersion $NodeMajor
    }

    $ZipName = "node-v$NodeVersion-win-x64.zip"
    $ZipPath = Join-Path $TmpDir $ZipName
    $Url = "https://nodejs.org/dist/v$NodeVersion/$ZipName"

    Save-File $Url $ZipPath
    Expand-ZipToCleanDir $ZipPath $NodeDir -StripSingleTopDirectory

    # npm のグローバル領域とキャッシュも、このフォルダ配下へ閉じ込める。
    New-Dir (Join-Path $NodeDir "npm-global")
    New-Dir (Join-Path $CacheDir "npm")
}

<#
.SYNOPSIS
ポータブル uv をインストールします。

.DESCRIPTION
GitHub Releases から uv の Windows 用 zip を取得し、.local\opt\uv に展開します。
#>
function Install-Uv {
    if (-not $UvVersion) {
        $script:UvVersion = Get-LatestGitHubTag "astral-sh/uv"
    }

    # uv の GitHub リリースタグは 0.11.15 のように v なしなので、入力値も v なしへ正規化する。
    $Tag = if ($UvVersion.StartsWith("v")) { $UvVersion.Substring(1) } else { $UvVersion }
    $ZipName = "uv-x86_64-pc-windows-msvc.zip"
    $CacheName = "uv-$Tag-x86_64-pc-windows-msvc.zip"
    $ZipPath = Join-Path $TmpDir $CacheName
    $Url = "https://github.com/astral-sh/uv/releases/download/$Tag/$ZipName"

    Save-File $Url $ZipPath
    Expand-ZipToCleanDir $ZipPath $UvDir -StripSingleTopDirectory
}

<#
.SYNOPSIS
ポータブル jq をインストールします。

.DESCRIPTION
GitHub Releases から jq の Windows 用 exe を取得し、.local\opt\jq\jq.exe として配置します。
#>
function Install-Jq {
    if (-not $JqVersion) {
        $script:JqVersion = Get-LatestGitHubTag "jqlang/jq"
    }

    $Tag = if ($JqVersion.StartsWith("jq-")) { $JqVersion } else { "jq-$JqVersion".Replace("jq-v", "jq-") }
    $ExeName = "jq-windows-amd64.exe"
    $CacheName = "$Tag-$ExeName"
    $ExePath = Join-Path $TmpDir $CacheName
    $Url = "https://github.com/jqlang/jq/releases/download/$Tag/$ExeName"

    Save-File $Url $ExePath
    Remove-DirContents $JqDir
    Copy-Item -LiteralPath $ExePath -Destination (Join-Path $JqDir "jq.exe") -Force
}

<#
.SYNOPSIS
ポータブル pandoc をインストールします。

.DESCRIPTION
GitHub Releases から pandoc の Windows 用 zip を取得し、.local\opt\pandoc に展開します。
#>
function Install-Pandoc {
    if (-not $PandocVersion) {
        $script:PandocVersion = Get-LatestGitHubTag "jgm/pandoc"
    }

    # pandoc のタグは "3.9.0.2" のように v なし。
    # 入力値に v が付いていても付いていなくても両方受け付ける。
    $Tag = $PandocVersion.TrimStart("v")          # タグとして使う（v なし）
    $Ver = $Tag                                    # ファイル名にも v なし
    $ZipName = "pandoc-$Ver-windows-x86_64.zip"
    $ZipPath = Join-Path $TmpDir $ZipName
    $Url = "https://github.com/jgm/pandoc/releases/download/$Tag/$ZipName"

    Save-File $Url $ZipPath
    Expand-ZipToCleanDir $ZipPath $PandocDir -StripSingleTopDirectory
}

<#
.SYNOPSIS
VSCode の初期設定ファイルを作成します。

.DESCRIPTION
Portable Mode 用の vscode\data 配下に argv.json と settings.json を作成します。
統合ターミナルの既定プロファイルは Windows PowerShell に設定します。
#>
function Write-VsCodeSettings {
    New-Dir (Join-Path $VsCodeDir "data\user-data\User")
    New-Dir (Join-Path $VsCodeDir "data\user-data\User\globalStorage")

    # 空の argv.json は VSCode 起動時に JSON パースエラーになるため、明示的に {} を置く。
    Set-Content -LiteralPath (Join-Path $VsCodeDir "data\argv.json") -Value "{}" -Encoding UTF8

    # 統合ターミナルは pwsh ではなく Windows PowerShell 5.1 を既定にする。
    $SettingsPath = Join-Path $VsCodeDir "data\user-data\User\settings.json"
    $SettingsJson = @'
{
    "terminal.integrated.defaultProfile.windows": "Windows PowerShell"
}
'@
    Set-Content -LiteralPath $SettingsPath -Value $SettingsJson -Encoding UTF8
}

<#
.SYNOPSIS
VSCode 拡張機能をインストールします。

.DESCRIPTION
vscode\bin\code.cmd を使って、スクリプト内の拡張機能リストを .local\opt\vscode\data\extensions にインストールします。
インストール用 user-data とログは .tmp 配下を使います。
#>
function Install-VsCodeExtensions {
    $CodeCmd = Join-Path $VsCodeDir "bin\code.cmd"
    $UserDataDir = Join-Path $TmpDir "vscode-extension-install-user-data"
    $ExtensionsDir = Join-Path $VsCodeDir "data\extensions"
    $ExtensionLog = Join-Path $TmpDir "vscode-extension-install.log"

    if (-not (Test-Path -LiteralPath $CodeCmd)) {
        throw "VSCode CLI was not found: $CodeCmd"
    }

    New-Dir $UserDataDir
    New-Dir (Join-Path $UserDataDir "User")
    New-Dir (Join-Path $UserDataDir "User\globalStorage")
    if (Test-Path -LiteralPath $ExtensionLog) {
        Remove-Item -LiteralPath $ExtensionLog -Force
    }

    foreach ($ExtensionId in $VsCodeExtensions) {
        Write-Host "   Installing extension: $ExtensionId"
        $Output = & $CodeCmd `
            --user-data-dir $UserDataDir `
            --extensions-dir $ExtensionsDir `
            --install-extension $ExtensionId `
            --force 2>&1

        if ($Output) {
            Add-Content -LiteralPath $ExtensionLog -Value $Output
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install VSCode extension: $ExtensionId"
        }
    }

    Write-Host "   Extension install log: $ExtensionLog"
}

<#
.SYNOPSIS
ポータブル VSCode をインストールします。

.DESCRIPTION
Microsoft 公式の update API から Windows x64 archive を取得し、.local\opt\vscode に展開します。
data フォルダを作成して Portable Mode を有効化し、初期設定と拡張機能のインストールも行います。
#>
function Install-VsCode {
    # バージョン未指定なら update API の "latest" を問い合わせる。
    if (-not $VsCodeVersion) {
        $Info = Invoke-Json "https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest"
        $script:VsCodeVersion = $Info.name          # 例: "1.100.2"
        $DownloadUrl = $Info.url
    } else {
        # バージョン固定の場合は URL を直接組み立てる。
        $DownloadUrl = "https://update.code.visualstudio.com/$VsCodeVersion/win32-x64-archive/stable"
    }

    $ZipName = "vscode-$VsCodeVersion-win32-x64.zip"
    $ZipPath = Join-Path $TmpDir $ZipName

    # update API が返す url は署名付き CDN URL のため Save-File に直接渡す。
    Save-File $DownloadUrl $ZipPath
    Expand-ZipToCleanDir $ZipPath $VsCodeDir

    # data/ フォルダを作成して Portable モードを有効化する。
    # サブフォルダも事前に作っておくと初回起動が速い。
    New-Dir (Join-Path $VsCodeDir "data")
    New-Dir (Join-Path $VsCodeDir "data\user-data")
    New-Dir (Join-Path $VsCodeDir "data\extensions")
    New-Dir (Join-Path $VsCodeDir "data\tmp")

    Write-VsCodeSettings
    Install-VsCodeExtensions
}

<#
.SYNOPSIS
起動用と検証用の cmd ファイルを生成します。

.DESCRIPTION
start-pdev.cmd はポータブル PATH を設定して VSCode を起動します。
verify-pdev.cmd は各ツールのバージョンを確認し、想定した Python/Node.js 系列であることを検証します。
#>
function Write-CmdFiles {
    $PythonMinorPattern = $PythonMinor -replace "\.", "\."
    $NodeMajorPattern = $NodeMajor -replace "\.", "\."

    $StartCmd = @'
@echo off
chcp 65001 >nul
setlocal
set "PDEV_ROOT=%~dp0"
set "PYTHONNOUSERSITE=1"
set "PIP_CACHE_DIR=%PDEV_ROOT%.cache\pip"
set "PIP_DISABLE_PIP_VERSION_CHECK=1"
set "UV_CACHE_DIR=%PDEV_ROOT%.cache\uv"
set "PDEV_OPT=%PDEV_ROOT%.local\opt"
set "UV_PYTHON_INSTALL_DIR=%PDEV_OPT%\uv\python"
set "UV_TOOL_DIR=%PDEV_OPT%\uv\tools"
set "UV_TOOL_BIN_DIR=%PDEV_OPT%\uv\bin"
set "NPM_CONFIG_PREFIX=%PDEV_OPT%\node\npm-global"
set "NPM_CONFIG_CACHE=%PDEV_ROOT%.cache\npm"
set "PATH=%PDEV_OPT%\python;%PDEV_OPT%\python\Scripts;%PDEV_OPT%\node;%PDEV_OPT%\node\npm-global;%PDEV_OPT%\node\npm-global\bin;%PDEV_OPT%\uv;%PDEV_OPT%\uv\bin;%PDEV_OPT%\jq;%PDEV_OPT%\pandoc;%PDEV_OPT%\vscode;%PDEV_OPT%\vscode\bin;%PATH%"

if not exist "%PDEV_OPT%\vscode\Code.exe" (
  echo VSCode executable was not found: "%PDEV_OPT%\vscode\Code.exe"
  exit /b 1
)

start "" "%PDEV_OPT%\vscode\Code.exe" --new-window "%PDEV_ROOT%."
exit /b 0
'@

    $VerifyCmd = @"
@echo off
chcp 65001 >nul
setlocal
set "PDEV_ROOT=%~dp0"
set "PYTHONNOUSERSITE=1"
set "PIP_CACHE_DIR=%PDEV_ROOT%.cache\pip"
set "PIP_DISABLE_PIP_VERSION_CHECK=1"
set "UV_CACHE_DIR=%PDEV_ROOT%.cache\uv"
set "PDEV_OPT=%PDEV_ROOT%.local\opt"
set "UV_PYTHON_INSTALL_DIR=%PDEV_OPT%\uv\python"
set "UV_TOOL_DIR=%PDEV_OPT%\uv\tools"
set "UV_TOOL_BIN_DIR=%PDEV_OPT%\uv\bin"
set "NPM_CONFIG_PREFIX=%PDEV_OPT%\node\npm-global"
set "NPM_CONFIG_CACHE=%PDEV_ROOT%.cache\npm"
set "PATH=%PDEV_OPT%\python;%PDEV_OPT%\python\Scripts;%PDEV_OPT%\node;%PDEV_OPT%\node\npm-global;%PDEV_OPT%\node\npm-global\bin;%PDEV_OPT%\uv;%PDEV_OPT%\uv\bin;%PDEV_OPT%\jq;%PDEV_OPT%\pandoc;%PDEV_OPT%\vscode;%PDEV_OPT%\vscode\bin;%PATH%"
for /F "delims=" %%A in ('echo prompt `$E ^| cmd') do set "ESC=%%A"

echo 🐍 [python]
python --version || exit /b 1
echo.

echo 📦 [pip]
python -m pip --version || exit /b 1
echo.

echo 🟩 [node]
node --version || exit /b 1
echo.

echo 📦 [npm]
cmd.exe /d /c npm --version || exit /b 1
echo.

echo ⚡ [uv]
uv --version || exit /b 1
echo.

echo 🔧 [jq]
jq --version || exit /b 1
echo.

echo 📄 [pandoc]
pandoc --version || exit /b 1
echo.

echo 🖥️  [vscode]
cmd.exe /d /c Code.cmd --version || exit /b 1
echo.

echo ✅ Portable dev environment is ready.
"@

    Set-Content -LiteralPath (Join-Path $Root "start-pdev.cmd") -Value $StartCmd -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root "verify-pdev.cmd") -Value $VerifyCmd -Encoding UTF8
}

# インストール先とキャッシュ先を先に作成しておく。
New-Dir $CacheDir
New-Dir $TmpDir
New-Dir $LocalDir
New-Dir $OptDir
New-Dir (Join-Path $CacheDir "pip")
New-Dir (Join-Path $CacheDir "uv")
New-Dir (Join-Path $CacheDir "npm")
New-Dir $PythonDir
New-Dir $NodeDir
New-Dir $UvDir
New-Dir $JqDir
New-Dir $PandocDir
New-Dir $VsCodeDir

Write-Host "🐍 Installing Python $PythonMinor..." -ForegroundColor Cyan
Install-Python
Write-Host ""

Write-Host "🟩 Installing Node.js $NodeMajor..." -ForegroundColor Cyan
Install-Node
Write-Host ""

Write-Host "⚡ Installing uv..." -ForegroundColor Cyan
Install-Uv
Write-Host ""

Write-Host "🔧 Installing jq..." -ForegroundColor Cyan
Install-Jq
Write-Host ""

Write-Host "📄 Installing pandoc..." -ForegroundColor Cyan
Install-Pandoc
Write-Host ""

Write-Host "🖥️  Installing VSCode..." -ForegroundColor Cyan
Install-VsCode
Write-Host ""

Write-Host "📜 Creating command files..." -ForegroundColor Cyan
Write-CmdFiles
Write-Host ""

Write-Host ""
Write-Host "✅ Created portable dev environment:" -ForegroundColor Green
Write-Host "   🐍 python  $PythonVersion"
Write-Host "   🟩 node    $NodeVersion"
Write-Host "   ⚡ uv      $UvVersion"
Write-Host "   🔧 jq      $JqVersion"
Write-Host "   📄 pandoc  $PandocVersion"
Write-Host "   🖥️  vscode  $VsCodeVersion"
Write-Host ""
Write-Host "▶️  Run verify-pdev.cmd to verify, or start-pdev.cmd to launch VSCode with portable PATH." -ForegroundColor Green
Write-Host "   🏃 Launch VSCode with portable PATH. : start-pdev.cmd"
Write-Host "   🔍 Verify environment.               : verify-pdev.cmd"
Write-Host ""
