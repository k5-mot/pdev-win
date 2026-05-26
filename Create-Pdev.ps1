<#
.SYNOPSIS
Desktop 配下にポータブル開発環境を作成します。

.DESCRIPTION
指定したインストール先に Scoop と開発ツールを導入し、VS Code 用の
user-data / extensions ディレクトリと起動用バッチファイルを作成します。

.PARAMETER InstallRoot
ポータブル開発環境を作成するルートディレクトリです。
この配下に .local と .config を作成します。
既定値はユーザーの Desktop です。

.PARAMETER PythonVersion
Scoop でインストールする Python のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER NodejsVersion
Scoop でインストールする Node.js のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER UvVersion
Scoop でインストールする uv のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER JqVersion
Scoop でインストールする jq のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER PandocVersion
Scoop でインストールする pandoc のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER VscodeVersion
Scoop でインストールする Visual Studio Code のバージョンです。
未指定の場合は Scoop の最新バージョンをインストールします。

.PARAMETER StartBatPath
生成する起動用バッチファイルのパスです。
未指定の場合は InstallRoot\start.bat です。

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1

Desktop 配下に .local と .config を作成し、最新バージョンの各ツールをインストールします。

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\Create-Pdev.ps1 -InstallRoot C:\pdev -PythonVersion 3.12.10 -NodejsVersion 22.16.0

C:\pdev に環境を作成し、Python と Node.js のバージョンを指定してインストールします。
#>
[CmdletBinding()]
param(
    [Alias("RootDir", "InstallDir", "InstallPath")]
    [string]$InstallRoot = ([Environment]::GetFolderPath("Desktop")),

    [string]$PythonVersion,

    [Alias("NodeVersion")]
    [string]$NodejsVersion,

    [string]$UvVersion,

    [string]$JqVersion,

    [string]$PandocVersion,

    [Alias("CodeVersion")]
    [string]$VscodeVersion,

    [string]$StartBatPath
)

$ErrorActionPreference = "Stop"

$RootDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
$LocalDir = Join-Path $RootDir ".local"
$OptDir = Join-Path $LocalDir "opt"
$TmpDir = Join-Path $LocalDir "tmp"
$BinDir = Join-Path $LocalDir "bin"
$ConfigDir = Join-Path $RootDir ".config"
$HomeDir = Join-Path $LocalDir "home"
$CacheDir = Join-Path $LocalDir "cache"
$PythonUserBaseDir = Join-Path $LocalDir "python-user"
$PipConfigDir = Join-Path $ConfigDir "pip"
$PipConfigFile = Join-Path $PipConfigDir "pip.ini"
$AppDataDir = Join-Path $ConfigDir "appdata\Roaming"
$LocalAppDataDir = Join-Path $LocalDir "appdata\Local"

$ScoopDir = Join-Path $OptDir "scoop"
$ScoopCacheDir = $TmpDir
$VscodeConfigDir = Join-Path $ConfigDir "vscode"
$VscodeDataDir = Join-Path $VscodeConfigDir "user-data"
$VscodeExtDir = Join-Path $VscodeConfigDir "extensions"

if ([string]::IsNullOrWhiteSpace($StartBatPath)) {
    $StartBatPath = Join-Path $RootDir "start.bat"
}
$StartBat = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StartBatPath)

$ToolPackages = [ordered]@{
    python = $PythonVersion
    nodejs = $NodejsVersion
    uv     = $UvVersion
    jq     = $JqVersion
    pandoc = $PandocVersion
    vscode = $VscodeVersion
}

function Get-ScoopPackageSpec {
    <#
    .SYNOPSIS
    Scoop に渡すパッケージ指定文字列を返します。

    .DESCRIPTION
    バージョンが指定された場合は name@version、未指定の場合は name を返します。

    .PARAMETER Name
    Scoop パッケージ名です。

    .PARAMETER Version
    インストールするバージョンです。
    空文字または未指定の場合はバージョン指定を行いません。

    .EXAMPLE
    Get-ScoopPackageSpec -Name python -Version 3.12.10

    python@3.12.10 を返します。
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $Name
    }

    return "$Name@$Version"
}

function New-PortableDirectories {
    <#
    .SYNOPSIS
    ポータブル開発環境で使用するディレクトリを作成します。

    .DESCRIPTION
    .local、.config、Scoop 本体、キャッシュ、HOME、AppData、pip 設定、
    VS Code 設定、拡張機能などを配置するディレクトリをインストール先の配下に作成します。

    .EXAMPLE
    New-PortableDirectories
    #>
    $dirs = @(
        $RootDir,
        $LocalDir,
        $OptDir,
        $TmpDir,
        $BinDir,
        $ConfigDir,
        $HomeDir,
        $CacheDir,
        $PythonUserBaseDir,
        $PipConfigDir,
        $AppDataDir,
        $LocalAppDataDir,
        $ScoopDir,
        $VscodeConfigDir,
        $VscodeDataDir,
        $VscodeExtDir,
        (Split-Path -Parent $StartBat)
    )

    foreach ($dir in $dirs) {
        if ($dir) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
}

function Set-PortableEnvironment {
    <#
    .SYNOPSIS
    Scoop と PATH の環境変数を設定します。

    .DESCRIPTION
    ユーザー環境変数 SCOOP / SCOOP_CACHE と Path にポータブル環境の
    bin / shims を追加します。現在の PowerShell セッションでは HOME / USERPROFILE /
    APPDATA / LOCALAPPDATA / TEMP / TMP / PIP_CONFIG_FILE / PYTHONUSERBASE も InstallRoot 配下に向け、
    Scoop の post_install や各ツールの設定保存先をポータブル環境内に隔離します。

    .EXAMPLE
    Set-PortableEnvironment
    #>
    [Environment]::SetEnvironmentVariable("SCOOP", $ScoopDir, "User")
    [Environment]::SetEnvironmentVariable("SCOOP_CACHE", $ScoopCacheDir, "User")

    $env:SCOOP = $ScoopDir
    $env:SCOOP_CACHE = $ScoopCacheDir
    $env:PDEV_ROOT = $RootDir
    $env:HOME = $HomeDir
    $env:USERPROFILE = $HomeDir
    $env:APPDATA = $AppDataDir
    $env:LOCALAPPDATA = $LocalAppDataDir
    $env:XDG_CONFIG_HOME = $ConfigDir
    $env:XDG_CACHE_HOME = $CacheDir
    $env:TEMP = $TmpDir
    $env:TMP = $TmpDir
    $env:PIP_CONFIG_FILE = $PipConfigFile
    $env:PIP_CACHE_DIR = Join-Path $CacheDir "pip"
    $env:PYTHONUSERBASE = $PythonUserBaseDir

    $scoopShimDir = Join-Path $ScoopDir "shims"
    $pathItems = @($BinDir, $scoopShimDir)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $currentItems = @()
    if ($userPath) {
        $currentItems = $userPath -split ";" | Where-Object { $_ -ne "" }
    }

    for ($i = $pathItems.Count - 1; $i -ge 0; $i--) {
        $item = $pathItems[$i]
        if ($currentItems -notcontains $item) {
            $userPath = "$item;$userPath"
        }
    }

    [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
    $env:Path = ($pathItems + @($env:Path)) -join ";"
}

function Install-ScoopPortable {
    <#
    .SYNOPSIS
    Scoop をポータブル環境にインストールします。

    .DESCRIPTION
    Scoop が未インストールの場合、公式インストーラーを一時ディレクトリに保存し、
    Scoop 本体をインストール先の opt\scoop に配置します。

    .EXAMPLE
    Install-ScoopPortable
    #>
    $scoopCmd = Join-Path $ScoopDir "shims\scoop.cmd"

    if (Test-Path $scoopCmd) {
        Write-Host "[SKIP] Scoop already installed."
        return
    }

    $installer = Join-Path $TmpDir "scoop-install.ps1"
    Invoke-RestMethod "https://get.scoop.sh" -OutFile $installer

    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer `
        -ScoopDir $ScoopDir `
        -ScoopGlobalDir $ScoopDir
}

function Add-ScoopBuckets {
    <#
    .SYNOPSIS
    必要な Scoop bucket を追加します。

    .DESCRIPTION
    main と extras bucket を追加します。既に存在する場合のエラーは無視します。

    .EXAMPLE
    Add-ScoopBuckets
    #>
    scoop bucket add main 2>$null
    scoop bucket add extras 2>$null
}

function Install-DevTools {
    <#
    .SYNOPSIS
    開発ツールを Scoop でインストールします。

    .DESCRIPTION
    Python、Node.js、uv、jq、pandoc、Visual Studio Code をインストールします。
    バージョン指定があるツールは Scoop の name@version 形式でインストールします。
    最後に Python の ensurepip を実行し、pip を更新します。

    .EXAMPLE
    Install-DevTools
    #>
    foreach ($packageName in $ToolPackages.Keys) {
        $packageSpec = Get-ScoopPackageSpec -Name $packageName -Version $ToolPackages[$packageName]
        scoop install $packageSpec
    }

    python -m ensurepip --upgrade
    python -m pip install --upgrade pip
}

function New-ToolLinks {
    <#
    .SYNOPSIS
    opt 配下に各ツールへの junction を作成します。

    .DESCRIPTION
    Scoop の実体は opt\scoop\apps 配下にあるため、保守しやすい入口として
    opt\python や opt\nodejs などの junction を作成します。

    .EXAMPLE
    New-ToolLinks
    #>
    foreach ($tool in $ToolPackages.Keys) {
        $target = Join-Path $ScoopDir "apps\$tool\current"
        $link = Join-Path $OptDir $tool

        if (Test-Path $link) {
            continue
        }

        if (Test-Path $target) {
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        }
    }
}

function Test-PortableCommands {
    <#
    .SYNOPSIS
    PATH 上のコマンド存在確認を行います。

    .DESCRIPTION
    開発環境で必要なコマンドが現在の PATH から解決できるかを検証します。
    見つからないコマンドがある場合は例外を送出します。

    .EXAMPLE
    Test-PortableCommands
    #>
    $commands = @(
        "python",
        "pip",
        "node",
        "npm",
        "uv",
        "jq",
        "pandoc",
        "code"
    )

    foreach ($cmd in $commands) {
        $resolved = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $resolved) {
            throw "[NG] PATH に $cmd が見つかりません。"
        }

        Write-Host "[OK] $cmd -> $($resolved.Source)"
    }
}

function New-StartBat {
    <#
    .SYNOPSIS
    VS Code 起動用のバッチファイルを作成します。

    .DESCRIPTION
    PATH、HOME、USERPROFILE、APPDATA、LOCALAPPDATA、TEMP、TMP、pip 設定、
    Python user base をポータブル環境に向け、必要コマンドを検証したあと、
    ポータブル環境内の user-data / extensions を使って VS Code を起動する
    バッチファイルを作成します。

    .EXAMPLE
    New-StartBat
    #>
    $content = @"
@echo off
setlocal

set "ROOT=$RootDir"
set "LOCAL=%ROOT%\.local"
set "OPT=%LOCAL%\opt"
set "BIN=%LOCAL%\bin"
set "TMP=%LOCAL%\tmp"
set "CONFIG=%ROOT%\.config"
set "HOME=%LOCAL%\home"
set "USERPROFILE=%HOME%"
set "APPDATA=%CONFIG%\appdata\Roaming"
set "LOCALAPPDATA=%LOCAL%\appdata\Local"
set "XDG_CONFIG_HOME=%CONFIG%"
set "XDG_CACHE_HOME=%LOCAL%\cache"
set "TEMP=%LOCAL%\tmp"
set "TMP=%LOCAL%\tmp"
set "PIP_CONFIG_FILE=%CONFIG%\pip\pip.ini"
set "PIP_CACHE_DIR=%LOCAL%\cache\pip"
set "PYTHONUSERBASE=%LOCAL%\python-user"
set "PDEV_ROOT=%ROOT%"

set "SCOOP=%OPT%\scoop"
set "SCOOP_CACHE=%TMP%"
set "PATH=%BIN%;%SCOOP%\shims;%PATH%"

echo [PATH verification]
where python || exit /b 1
where pip || exit /b 1
where node || exit /b 1
where npm || exit /b 1
where uv || exit /b 1
where jq || exit /b 1
where pandoc || exit /b 1
where code || exit /b 1

echo.
echo [versions]
python --version
pip --version
node --version
npm --version
uv --version
jq --version
pandoc --version
code --version

echo.
echo [start vscode]
start "" code --user-data-dir "%CONFIG%\vscode\user-data" --extensions-dir "%CONFIG%\vscode\extensions"

endlocal
"@

    Set-Content -Path $StartBat -Value $content -Encoding ASCII
}

New-PortableDirectories
Set-PortableEnvironment

Push-Location $RootDir
try {
    Install-ScoopPortable
    Add-ScoopBuckets
    Install-DevTools
    New-ToolLinks
    New-StartBat
    Test-PortableCommands
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "完了しました。"
Write-Host "Root       : $RootDir"
Write-Host ".local     : $LocalDir"
Write-Host "opt        : $OptDir"
Write-Host "tmp/cache  : $TmpDir"
Write-Host "config     : $ConfigDir"
Write-Host "home       : $HomeDir"
Write-Host "appdata    : $AppDataDir"
Write-Host "pip config : $PipConfigFile"
Write-Host "start.bat  : $StartBat"
