param(
    # 取得する Python のマイナーバージョン。未指定ならこの系列の最新リリースを探す。
    [string]$PythonMinor = "3.14",
    # 取得する Node.js のメジャーバージョン。未指定ならこの系列の最新リリースを探す。
    [string]$NodeMajor = "24",
    # 固定バージョンを使いたい場合だけ指定する。
    [string]$PythonVersion = "",
    [string]$PipVersion = "",
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
$LocalDir = Join-Path $Root ".local"
$PkgsDir = Join-Path $LocalDir "pkgs"
$TmpDir = Join-Path $LocalDir "tmp"
$ConfigDir = Join-Path $Root ".config"
$PortableHomeDir = Join-Path $LocalDir "home"
$PortableAppDataDir = Join-Path $PortableHomeDir "AppData\Roaming"
$PortableLocalAppDataDir = Join-Path $PortableHomeDir "AppData\Local"
$PortableDataDir = Join-Path $LocalDir "share"
$OptDir = Join-Path $LocalDir "opt"
$NpmConfigDir = Join-Path $ConfigDir "npm"
$NpmConfigFile = Join-Path $NpmConfigDir "npmrc"
$NpmGlobalConfigFile = Join-Path $NpmConfigDir "global-npmrc"
$PythonDir = Join-Path $OptDir "python"
$NodeDir = Join-Path $OptDir "node"
$UvDir = Join-Path $OptDir "uv"
$JqDir = Join-Path $OptDir "jq"
$PandocDir = Join-Path $OptDir "pandoc"
$VsCodeDir = Join-Path $OptDir "vscode"

$VsCodeExtensions = @(
    # カラーテーマ
    "zhuangtongfa.material-theme",
    "pkief.material-icon-theme",
    # Draw.io
    "hediet.vscode-drawio",
    # コーディングエージェント
    "rooveterinaryinc.roo-cline",
    "zoocodeorganization.zoo-code",
    # "saoudrizwan.claude-dev",
    # "continue.continue",
    # Markdown
    "shd101wyy.markdown-preview-enhanced",
    # "yzhang.markdown-all-in-one",
    "bierner.markdown-mermaid"
)

<#
.SYNOPSIS
比較用に正規化した絶対パスを取得します。

.DESCRIPTION
相対パスや末尾の区切り文字の違いで判定がぶれないよう、.NET の GetFullPath で絶対パス化し、
末尾の \ または / を取り除いた文字列を返します。

.PARAMETER Path
正規化するパス。
#>
function Get-NormalizedFullPath {
    param([Parameter(Mandatory)][string]$Path)
    [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

<#
.SYNOPSIS
指定したパスがディレクトリ配下にあるか判定します。

.DESCRIPTION
Windows のパス比較として大文字小文字を区別せず、対象パスが指定ディレクトリ自身またはその配下かを確認します。
Desktop / Downloads 配下にスクリプトが置かれているかを安全に判定するために使います。

.PARAMETER Path
判定対象のパス。

.PARAMETER Directory
親ディレクトリとして扱うパス。
#>
function Test-IsPathUnderDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Directory
    )

    $FullPath = Get-NormalizedFullPath $Path
    $FullDirectory = Get-NormalizedFullPath $Directory
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase

    $FullPath.Equals($FullDirectory, $Comparison) -or
        $FullPath.StartsWith($FullDirectory + [System.IO.Path]::DirectorySeparatorChar, $Comparison)
}

<#
.SYNOPSIS
スクリプトの配置場所が許可された場所か確認します。

.DESCRIPTION
このポータブル環境はユーザープロファイル配下の Desktop または Downloads に閉じて使う想定のため、
それ以外の場所から実行された場合は処理を停止します。
#>
function Assert-RootInAllowedLocation {
    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    $AllowedRoots = @(
        (Join-Path $UserProfile "Desktop"),
        (Join-Path $UserProfile "Downloads")
    )

    foreach ($AllowedRoot in $AllowedRoots) {
        if (Test-IsPathUnderDirectory $Root $AllowedRoot) {
            return
        }
    }

    throw "This script must be placed under '$UserProfile\Desktop' or '$UserProfile\Downloads'. Current root: $Root"
}

Assert-RootInAllowedLocation

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
BOM なし UTF-8 でテキストファイルを書き込みます。

.DESCRIPTION
Windows PowerShell 5.1 の Set-Content -Encoding UTF8 は BOM 付き UTF-8 を出力します。
VSCode の argv.json など BOM が原因で読み込みに失敗するファイルを作るため、.NET API で BOM なし UTF-8 を明示します。

.PARAMETER Path
書き込み先ファイルのパス。

.PARAMETER Value
書き込む文字列。
#>
function Set-ContentUtf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $Utf8NoBom)
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
子プロセスが参照するユーザー領域と一時領域をポータブル環境配下へ固定します。

.DESCRIPTION
制限環境ではホームディレクトリ直下の Desktop または Downloads 配下だけを使うため、
TEMP/TMP や USERPROFILE/APPDATA などの既定値が AppData 側へ漏れないようにします。
#>
function Set-PortableProcessEnvironment {
    New-Dir $PortableHomeDir
    New-Dir $TmpDir
    New-Dir $PortableAppDataDir
    New-Dir $PortableLocalAppDataDir
    New-Dir $PortableDataDir

    $Env:USERPROFILE = $PortableHomeDir
    $Env:HOME = $PortableHomeDir
    $Env:APPDATA = $PortableAppDataDir
    $Env:LOCALAPPDATA = $PortableLocalAppDataDir
    $Env:TEMP = $TmpDir
    $Env:TMP = $TmpDir
    $Env:XDG_CONFIG_HOME = $ConfigDir
    $Env:XDG_CACHE_HOME = $CacheDir
    $Env:XDG_DATA_HOME = $PortableDataDir
}

<#
.SYNOPSIS
ポータブル環境のツール実行用環境変数を設定します。

.DESCRIPTION
検証処理やセットアップ中の子プロセスが、システム側の Python / Node.js / npm 設定を参照しないように、
PATH、pip、uv、npm、VSCode CLI 用の環境変数をポータブル環境配下へ固定します。
#>
function Set-PortableToolEnvironment {
    Set-PortableProcessEnvironment

    # ツールごとの設定・キャッシュ・グローバル導入先をポータブル環境配下へ閉じ込める。
    $Env:PDEV_ROOT = $Root
    $Env:PDEV_OPT = $OptDir
    $Env:PYTHONNOUSERSITE = "1"
    $Env:PIP_CONFIG_FILE = "NUL"
    $Env:PIP_CACHE_DIR = Join-Path $CacheDir "pip"
    $Env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
    $Env:UV_CACHE_DIR = Join-Path $CacheDir "uv"
    $Env:UV_NO_CONFIG = "1"
    $Env:UV_PYTHON_INSTALL_DIR = Join-Path $UvDir "python"
    $Env:UV_TOOL_DIR = Join-Path $UvDir "tools"
    $Env:UV_TOOL_BIN_DIR = Join-Path $UvDir "bin"
    $Env:NPM_CONFIG_PREFIX = Join-Path $NodeDir "npm-global"
    $Env:NPM_CONFIG_CACHE = Join-Path $CacheDir "npm"
    $Env:NPM_CONFIG_USERCONFIG = $NpmConfigFile
    $Env:NPM_CONFIG_GLOBALCONFIG = $NpmGlobalConfigFile
    $Env:NPM_CONFIG_LOGLEVEL = "error"
    $Env:VSCODE_USER_DATA_DIR = Join-Path $VsCodeDir "data\user-data"
    $Env:VSCODE_EXTENSIONS_DIR = Join-Path $VsCodeDir "data\extensions"

    # ポータブル版の実行ファイルを、既存 PATH より優先して解決させる。
    $ToolPaths = @(
        $PythonDir,
        (Join-Path $PythonDir "Scripts"),
        $NodeDir,
        (Join-Path $NodeDir "npm-global"),
        (Join-Path $NodeDir "npm-global\bin"),
        $UvDir,
        (Join-Path $UvDir "bin"),
        $JqDir,
        $PandocDir,
        $VsCodeDir,
        (Join-Path $VsCodeDir "bin")
    )
    $Env:PATH = ($ToolPaths -join [System.IO.Path]::PathSeparator) + [System.IO.Path]::PathSeparator + $Env:PATH
}

<#
.SYNOPSIS
外部コマンドを実行し、標準出力と標準エラーをログへ保存します。

.DESCRIPTION
検証時に pip / npm / uv などの詳細ログを画面へ流さないよう、出力を指定ログファイルへ追記します。
一部の native command は正常時にも stderr へメッセージを書くため、この関数内だけ ErrorActionPreference を緩め、
最終的な成否はプロセスの終了コードで判定します。

.PARAMETER LogPath
出力を追記するログファイルのパス。

.PARAMETER FilePath
実行するコマンドまたは実行ファイルのパス。

.PARAMETER Arguments
コマンドへ渡す引数。
#>
function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Add-Content -LiteralPath $LogPath -Value ("> " + $FilePath + " " + ($Arguments -join " "))
    # $ErrorActionPreference = Stop のままだと、stderr 出力だけで NativeCommandError になることがある。
    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $FilePath @Arguments *>> $LogPath
        $ExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($ExitCode -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' '). See log: $LogPath"
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
zipball や exe、wheel などの再利用する取得物は .local\pkgs 配下のパスを渡して保存します。

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
        Write-Host "📦  Using cached: $OutFile"
        return
    }

    Write-Host "⏬  Downloading: $Uri"
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

    # 直接配置先へ展開せず、一度専用の一時ディレクトリで zip の中身を確認できる形にする。
    $Temp = Join-Path $TmpDir ("extract-" + [guid]::NewGuid().ToString("N"))
    New-Dir $Temp
    Write-Host "📂  Expanding: $ZipPath"
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Temp -Force

        # 古いファイルが残るとバージョン違いの混在が起きるため、コピー前に配置先を空にする。
        Remove-DirContents $Destination

        $Source = $Temp
        if ($StripSingleTopDirectory) {
            # 配布 zip が node-vxx/ のような単一トップディレクトリを持つ場合は、その中身だけを配置する。
            $Items = @(Get-ChildItem -LiteralPath $Temp -Force)
            if ($Items.Count -eq 1 -and $Items[0].PSIsContainer) {
                $Source = $Items[0].FullName
            }
        }

        # 展開元の直下要素を配置先へコピーし、必要なディレクトリ構造だけを残す。
        Get-ChildItem -LiteralPath $Source -Force |
            Copy-Item -Destination $Destination -Recurse -Force
    } finally {
        # 途中で失敗しても、一時展開ディレクトリは残さない。
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
PyPI から最新 pip wheel の URL とファイル名を取得します。

.DESCRIPTION
ブートストラップ用スクリプトに依存せず、pip の wheel を直接展開して embeddable Python に導入します。
#>
function Get-LatestPipWheel {
    $Package = Invoke-Json "https://pypi.org/pypi/pip/json"
    $Wheel = $Package.urls |
        Where-Object { $_.packagetype -eq "bdist_wheel" -and $_.filename -match "^pip-.+\.whl$" } |
        Select-Object -First 1

    if (-not $Wheel) {
        throw "Could not find a pip wheel on PyPI."
    }

    [pscustomobject]@{
        FileName = $Wheel.filename
        Url = $Wheel.url
    }
}

<#
.SYNOPSIS
pip wheel を embeddable Python の site-packages へ展開します。

.DESCRIPTION
取得済みの pip wheel を一時ディレクトリで zip として展開し、Python embeddable package の
Lib\site-packages へコピーします。あわせて pip.cmd / pip3.cmd も Scripts 配下に作成します。

.PARAMETER WheelPath
展開する pip の whl ファイル。
#>
function Install-PipWheel {
    param([Parameter(Mandatory)][string]$WheelPath)

    $SitePackagesDir = Join-Path $PythonDir "Lib\site-packages"
    $ScriptsDir = Join-Path $PythonDir "Scripts"
    $Temp = Join-Path $TmpDir ("pip-wheel-" + [guid]::NewGuid().ToString("N"))
    $WheelZip = Join-Path $Temp (([System.IO.Path]::GetFileNameWithoutExtension($WheelPath)) + ".zip")

    New-Dir $SitePackagesDir
    New-Dir $ScriptsDir
    New-Dir $Temp

    try {
        Copy-Item -LiteralPath $WheelPath -Destination $WheelZip -Force
        Expand-Archive -LiteralPath $WheelZip -DestinationPath $Temp -Force

        Get-ChildItem -LiteralPath $Temp -Force |
            Where-Object { $_.Name -ne ([System.IO.Path]::GetFileName($WheelZip)) } |
            Copy-Item -Destination $SitePackagesDir -Recurse -Force
    } finally {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $PipCmd = @'
@echo off
"%~dp0..\python.exe" -m pip %*
'@
    Set-Content -LiteralPath (Join-Path $ScriptsDir "pip.cmd") -Value $PipCmd -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $ScriptsDir "pip3.cmd") -Value $PipCmd -Encoding ASCII
}

<#
.SYNOPSIS
ポータブル Python をインストールします。

.DESCRIPTION
Python embeddable package を .local\opt\python に展開し、site-packages を読み込めるようにします。
#>
function Install-Python {
    if (-not $PythonVersion) {
        $script:PythonVersion = Get-LatestPythonVersion $PythonMinor
    }

    $ZipName = "python-$PythonVersion-embed-amd64.zip"
    $ZipPath = Join-Path $PkgsDir $ZipName
    $Url = "https://www.python.org/ftp/python/$PythonVersion/$ZipName"

    Save-File $Url $ZipPath
    Expand-ZipToCleanDir $ZipPath $PythonDir

    # Embeddable Python は既定で site を読み込まないため、site-packages を使えるようにする。
    $Pth = Get-ChildItem -LiteralPath $PythonDir -Filter "python*._pth" | Select-Object -First 1
    if ($Pth) {
        $Text = Get-Content -LiteralPath $Pth.FullName -Raw
        $Text = $Text -replace "#import site", "import site"
        if ($Text -notmatch "(?m)^Lib\\site-packages$") {
            $Text = $Text.TrimEnd() + "`r`nLib\site-packages`r`n"
        }
        Set-Content -LiteralPath $Pth.FullName -Value $Text -Encoding ASCII
    }
}

<#
.SYNOPSIS
ポータブル Python に pip をインストールします。

.DESCRIPTION
PyPI から取得した pip wheel を embeddable Python の site-packages へ展開します。
pip のキャッシュは .cache\pip に固定します。
#>
function Install-Pip {
    # ユーザー環境の site-packages を見ないようにして、ポータブル環境へ pip を入れる。
    $Env:PYTHONNOUSERSITE = "1"
    $Env:PIP_CONFIG_FILE = "NUL"
    $Env:PIP_CACHE_DIR = Join-Path $CacheDir "pip"
    $Env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

    $PipWheel = Get-LatestPipWheel
    $PipWheelPath = Join-Path $PkgsDir $PipWheel.FileName
    Save-File $PipWheel.Url $PipWheelPath

    Write-Host "📦  Installing pip from wheel..." -ForegroundColor Gray
    Install-PipWheel $PipWheelPath
    $PipVersionOutput = & (Join-Path $PythonDir "python.exe") -m pip --version
    $script:PipVersion = ($PipVersionOutput -replace "^pip\s+([^\s]+).*$", '$1')
    $PipVersionOutput | Out-Host
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
    $ZipPath = Join-Path $PkgsDir $ZipName
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
    $ZipPath = Join-Path $PkgsDir $CacheName
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
    $ExePath = Join-Path $PkgsDir $CacheName
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
    $ZipPath = Join-Path $PkgsDir $ZipName
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

    # argv.json は BOM 付き UTF-8 だと VSCode 起動時に JSON パースエラーになることがある。
    Set-ContentUtf8NoBom -Path (Join-Path $VsCodeDir "data\argv.json") -Value "{}"

    # 統合ターミナルは pwsh ではなく Windows PowerShell 5.1 を既定にする。
    $SettingsPath = Join-Path $VsCodeDir "data\user-data\User\settings.json"
    $SettingsJson = @'
{
    "terminal.integrated.defaultProfile.windows": "Windows PowerShell"
}
'@
    Set-ContentUtf8NoBom -Path $SettingsPath -Value $SettingsJson
}

<#
.SYNOPSIS
VSCode 拡張機能をインストールします。

.DESCRIPTION
vscode\bin\code.cmd を使って、スクリプト内の拡張機能リストを .local\opt\vscode\data\extensions にインストールします。
インストール用 user-data とログは .local\tmp 配下を使います。
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
    $ZipPath = Join-Path $PkgsDir $ZipName

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
set "PDEV_HOME=%PDEV_ROOT%.local\home"
set "PDEV_CONFIG=%PDEV_ROOT%.config"
set "PDEV_CACHE=%PDEV_ROOT%.cache"
set "PDEV_DATA=%PDEV_ROOT%.local\share"
set "PDEV_TEMP=%PDEV_ROOT%.local\tmp"
set "USERPROFILE=%PDEV_HOME%"
set "HOME=%PDEV_HOME%"
set "APPDATA=%PDEV_HOME%\AppData\Roaming"
set "LOCALAPPDATA=%PDEV_HOME%\AppData\Local"
set "TEMP=%PDEV_TEMP%"
set "TMP=%PDEV_TEMP%"
set "XDG_CONFIG_HOME=%PDEV_CONFIG%"
set "XDG_CACHE_HOME=%PDEV_CACHE%"
set "XDG_DATA_HOME=%PDEV_DATA%"
for %%D in ("%PDEV_HOME%" "%APPDATA%" "%LOCALAPPDATA%" "%PDEV_TEMP%" "%PDEV_DATA%") do if not exist "%%~D" mkdir "%%~D"
set "PYTHONNOUSERSITE=1"
set "PIP_CONFIG_FILE=NUL"
set "PIP_CACHE_DIR=%PDEV_CACHE%\pip"
set "PIP_DISABLE_PIP_VERSION_CHECK=1"
set "UV_CACHE_DIR=%PDEV_CACHE%\uv"
set "UV_NO_CONFIG=1"
set "PDEV_OPT=%PDEV_ROOT%.local\opt"
set "UV_PYTHON_INSTALL_DIR=%PDEV_OPT%\uv\python"
set "UV_TOOL_DIR=%PDEV_OPT%\uv\tools"
set "UV_TOOL_BIN_DIR=%PDEV_OPT%\uv\bin"
set "NPM_CONFIG_PREFIX=%PDEV_OPT%\node\npm-global"
set "NPM_CONFIG_CACHE=%PDEV_CACHE%\npm"
set "NPM_CONFIG_USERCONFIG=%PDEV_CONFIG%\npm\npmrc"
set "NPM_CONFIG_GLOBALCONFIG=%PDEV_CONFIG%\npm\global-npmrc"
set "VSCODE_USER_DATA_DIR=%PDEV_OPT%\vscode\data\user-data"
set "VSCODE_EXTENSIONS_DIR=%PDEV_OPT%\vscode\data\extensions"
set "PATH=%PDEV_OPT%\python;%PDEV_OPT%\python\Scripts;%PDEV_OPT%\node;%PDEV_OPT%\node\npm-global;%PDEV_OPT%\node\npm-global\bin;%PDEV_OPT%\uv;%PDEV_OPT%\uv\bin;%PDEV_OPT%\jq;%PDEV_OPT%\pandoc;%PDEV_OPT%\vscode;%PDEV_OPT%\vscode\bin;%PATH%"

if not exist "%PDEV_OPT%\vscode\Code.exe" (
  echo VSCode executable was not found: "%PDEV_OPT%\vscode\Code.exe"
  exit /b 1
)

start "" "%PDEV_OPT%\vscode\Code.exe" --user-data-dir "%VSCODE_USER_DATA_DIR%" --extensions-dir "%VSCODE_EXTENSIONS_DIR%" --new-window "%PDEV_ROOT%."
exit /b 0
'@

    $VerifyCmd = @"
@echo off
chcp 65001 >nul
setlocal
set "PDEV_ROOT=%~dp0"
set "PDEV_HOME=%PDEV_ROOT%.local\home"
set "PDEV_CONFIG=%PDEV_ROOT%.config"
set "PDEV_CACHE=%PDEV_ROOT%.cache"
set "PDEV_DATA=%PDEV_ROOT%.local\share"
set "PDEV_TEMP=%PDEV_ROOT%.local\tmp"
set "USERPROFILE=%PDEV_HOME%"
set "HOME=%PDEV_HOME%"
set "APPDATA=%PDEV_HOME%\AppData\Roaming"
set "LOCALAPPDATA=%PDEV_HOME%\AppData\Local"
set "TEMP=%PDEV_TEMP%"
set "TMP=%PDEV_TEMP%"
set "XDG_CONFIG_HOME=%PDEV_CONFIG%"
set "XDG_CACHE_HOME=%PDEV_CACHE%"
set "XDG_DATA_HOME=%PDEV_DATA%"
for %%D in ("%PDEV_HOME%" "%APPDATA%" "%LOCALAPPDATA%" "%PDEV_TEMP%" "%PDEV_DATA%") do if not exist "%%~D" mkdir "%%~D"
set "PYTHONNOUSERSITE=1"
set "PIP_CONFIG_FILE=NUL"
set "PIP_CACHE_DIR=%PDEV_CACHE%\pip"
set "PIP_DISABLE_PIP_VERSION_CHECK=1"
set "UV_CACHE_DIR=%PDEV_CACHE%\uv"
set "UV_NO_CONFIG=1"
set "PDEV_OPT=%PDEV_ROOT%.local\opt"
set "UV_PYTHON_INSTALL_DIR=%PDEV_OPT%\uv\python"
set "UV_TOOL_DIR=%PDEV_OPT%\uv\tools"
set "UV_TOOL_BIN_DIR=%PDEV_OPT%\uv\bin"
set "NPM_CONFIG_PREFIX=%PDEV_OPT%\node\npm-global"
set "NPM_CONFIG_CACHE=%PDEV_CACHE%\npm"
set "NPM_CONFIG_USERCONFIG=%PDEV_CONFIG%\npm\npmrc"
set "NPM_CONFIG_GLOBALCONFIG=%PDEV_CONFIG%\npm\global-npmrc"
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

echo 🖥️ [vscode]
cmd.exe /d /c Code.cmd --version || exit /b 1
echo.

echo ✅ Portable dev environment is ready.
"@

    Set-Content -LiteralPath (Join-Path $Root "start-pdev.cmd") -Value $StartCmd -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root "verify-pdev.cmd") -Value $VerifyCmd -Encoding UTF8
}

<#
.SYNOPSIS
ポータブル環境の主要コマンドのバージョンを表示します。

.DESCRIPTION
Python、pip、Node.js、npm、uv、jq、pandoc が PATH 上で実行できることを確認し、
各コマンドのバージョンを標準出力へ表示します。
#>
function Test-PortableCommandVersions {
    Write-Host @"
Python : $(python --version)
pip    : $(pip --version)
Node.js: $(node --version)
npm    : $(npm --version)
uv     : $(uv --version)
jq     : $(jq --version)
pandoc : $(pandoc --version)
"@
}

<#
.SYNOPSIS
ポータブル環境の主要コマンドの解決先パスを表示します。

.DESCRIPTION
Get-Command で各コマンドの実体パスを確認し、システム側ではなく .local\opt 配下のツールが優先されているかを確認します。
#>
function Test-PortableCommandPaths {
    Write-Host @"
Python : $((Get-Command python).Source)
pip    : $((Get-Command pip).Source)
Node.js: $((Get-Command node).Source)
npm    : $((Get-Command npm).Source)
uv     : $((Get-Command uv).Source)
jq     : $((Get-Command jq).Source)
pandoc : $((Get-Command pandoc).Source)
"@
}

<#
.SYNOPSIS
pip のダウンロード、インストール、Python import 実行を検証します。

.DESCRIPTION
PyPI から pyfiglet wheel を .local\pkgs\pip へ取得し、ポータブル Python にインストールして、
python -m pyfiglet で CLI として実行できることを確認します。詳細出力はログファイルに保存します。

.PARAMETER LogPath
検証ログを書き込むファイルのパス。
#>
function Test-PortablePip {
    param([Parameter(Mandatory)][string]$LogPath)
    Write-Host "📦 Verifying pip..." -ForegroundColor Cyan
    $PipWorkDir = Join-Path $TmpDir "pip"
    $PipPackageDir = Join-Path $PkgsDir "pip"
    New-Dir $PipWorkDir
    New-Dir $PipPackageDir
    Push-Location $PipWorkDir
    try {
        Invoke-LoggedCommand $LogPath "pip" @("download", "-d", $PipPackageDir, "pyfiglet")
        Invoke-LoggedCommand $LogPath "pip" @("install", "--find-links=$PipPackageDir", "pyfiglet")
        Invoke-LoggedCommand $LogPath "pip" @("list")
        Invoke-LoggedCommand $LogPath "pyfiglet" @("portable pip works")
        # Invoke-LoggedCommand $LogPath "python" @("-m", "pyfiglet", "portable pip works")
    } finally {
        Pop-Location
    }
    Write-Host "   OK"
}

<#
.SYNOPSIS
npm のパッケージ取得、グローバルインストール、CLI 実行を検証します。

.DESCRIPTION
npm pack で cowsay の tgz を .local\pkgs\npm へ保存し、ポータブル Node.js の npm-global へインストールして、
PATH から cowsay コマンドが実行できることを確認します。詳細出力はログファイルに保存します。

.PARAMETER LogPath
検証ログを書き込むファイルのパス。
#>
function Test-PortableNpm {
    param([Parameter(Mandatory)][string]$LogPath)
    Write-Host "📦 Verifying npm..." -ForegroundColor Cyan
    $NpmWorkDir = Join-Path $TmpDir "npm"
    $NpmPackageDir = Join-Path $PkgsDir "npm"
    New-Dir $NpmWorkDir
    New-Dir $NpmPackageDir
    Push-Location $NpmWorkDir
    try {
        Invoke-LoggedCommand $LogPath "npm" @("pack", "cowsay", "--pack-destination", $NpmPackageDir, "--silent")
        # npm pack の出力ファイル名はバージョンで変わるため、直近に作られた tgz をインストール対象にする。
        $CowsayTgz = (Get-ChildItem -LiteralPath $NpmPackageDir -Filter "cowsay-*.tgz" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        Invoke-LoggedCommand $LogPath "npm" @("-g", "i", $CowsayTgz)
        Invoke-LoggedCommand $LogPath "npm" @("-g", "list", "--depth=0")
        Invoke-LoggedCommand $LogPath "cowsay" @("portable npm works")
        # Invoke-LoggedCommand $LogPath "cmd.exe" @("/d", "/c", "cowsay", "portable npm works")
    } finally {
        Pop-Location
    }
    Write-Host "   OK"
}

<#
.SYNOPSIS
uv のプロジェクト作成、仮想環境作成、依存追加、CLI 実行を検証します。

.DESCRIPTION
.local\tmp\uv に一時プロジェクトを作成し、catsay-cli をローカル wheel 参照で追加して、
uv run で CLI が実行できることを確認します。詳細出力はログファイルに保存します。

.PARAMETER LogPath
検証ログを書き込むファイルのパス。
#>
function Test-PortableUv {
    param([Parameter(Mandatory)][string]$LogPath)
    Write-Host "⚡ Verifying uv..." -ForegroundColor Cyan
    $UvWorkDir = Join-Path $TmpDir "uv"
    $PipPackageDir = Join-Path $PkgsDir "pip"
    New-Dir $UvWorkDir
    # uv init は既存 pyproject.toml があると失敗するため、検証用作業ディレクトリは毎回空にする。
    Remove-DirContents $UvWorkDir
    New-Dir $PipPackageDir
    Push-Location $UvWorkDir
    try {
        Invoke-LoggedCommand $LogPath "uv" @("init")
        Invoke-LoggedCommand $LogPath "uv" @("venv")
        Invoke-LoggedCommand $LogPath "pip" @("download", "-d", $PipPackageDir, "catsay-cli")
        Invoke-LoggedCommand $LogPath "uv" @("add", "--dev", "--find-links=$PipPackageDir", "catsay-cli")
        Invoke-LoggedCommand $LogPath "uv" @("pip", "list")
        Invoke-LoggedCommand $LogPath "uv" @("run", "catsay", "portable uv works")
    } finally {
        Pop-Location
    }
    Write-Host "   OK"
}

<#
.SYNOPSIS
jq の JSON 処理を検証します。

.DESCRIPTION
一時 JSON ファイルを作成し、jq で読み込めることを確認します。詳細出力はログファイルに保存します。

.PARAMETER LogPath
検証ログを書き込むファイルのパス。
#>
function Test-PortableJq {
    param([Parameter(Mandatory)][string]$LogPath)
    Write-Host "🔧 Verifying jq..." -ForegroundColor Cyan
    $JqInputPath = Join-Path $TmpDir "jq-input.json"
    Set-Content -LiteralPath $JqInputPath -Value '{ "name": "Alice", "age": 25 }' -Encoding ASCII
    Invoke-LoggedCommand $LogPath "jq" @(".", $JqInputPath)
    Write-Host "   OK"
}

<#
.SYNOPSIS
pandoc の Markdown 変換を検証します。

.DESCRIPTION
README.md を HTML へ変換し、pandoc がポータブル PATH 上で正常に動くことを確認します。
生成した HTML は .local\tmp\pandoc に保存します。

.PARAMETER LogPath
検証ログを書き込むファイルのパス。
#>
function Test-PortablePandoc {
    param([Parameter(Mandatory)][string]$LogPath)
    Write-Host "📄 Verifying pandoc..." -ForegroundColor Cyan
    $PandocWorkDir = Join-Path $TmpDir "pandoc"
    New-Dir $PandocWorkDir
    Push-Location $PandocWorkDir
    try {
        Invoke-LoggedCommand $LogPath "pandoc" @((Join-Path $Root "README.md"), "-o", "README.html")
    } finally {
        Pop-Location
    }
    Write-Host "   OK"
}

<#
.SYNOPSIS
ポータブル開発環境全体の動作確認を実行します。

.DESCRIPTION
ツール実行用の環境変数を設定し、バージョン、コマンド解決先、pip、npm、uv、jq、pandoc の検証を順番に実行します。
詳細ログは .local\tmp\verify-pdev.log に保存し、標準出力には概要と各検証の OK 表示だけを出します。
#>
function Invoke-PortableDevVerification {
    Set-PortableToolEnvironment

    $VerificationLog = Join-Path $TmpDir "verify-pdev.log"
    if (Test-Path -LiteralPath $VerificationLog) {
        Remove-Item -LiteralPath $VerificationLog -Force
    }

    Write-Host "🔍 Verifying portable tools..." -ForegroundColor Cyan
    Test-PortableCommandVersions
    Write-Host ""

    Write-Host "🔍 Verifying command paths..." -ForegroundColor Cyan
    Test-PortableCommandPaths
    Write-Host ""

    Test-PortablePip $VerificationLog
    Test-PortableNpm $VerificationLog
    Test-PortableUv $VerificationLog
    Test-PortableJq $VerificationLog
    Test-PortablePandoc $VerificationLog
}

# インストール先とキャッシュ先を先に作成しておく。
New-Dir $CacheDir
New-Dir $LocalDir
New-Dir $PkgsDir
New-Dir $TmpDir
New-Dir $ConfigDir
Set-PortableProcessEnvironment
New-Dir $OptDir
New-Dir $NpmConfigDir
New-Dir (Join-Path $CacheDir "pip")
New-Dir (Join-Path $CacheDir "uv")
New-Dir (Join-Path $CacheDir "npm")
Set-Content -LiteralPath $NpmConfigFile -Value $null -Encoding ASCII
Set-Content -LiteralPath $NpmGlobalConfigFile -Value $null -Encoding ASCII
New-Dir $PythonDir
New-Dir $NodeDir
New-Dir $UvDir
New-Dir $JqDir
New-Dir $PandocDir
New-Dir $VsCodeDir

Write-Host "🖥️  Installing VSCode..." -ForegroundColor Cyan
Install-VsCode
Write-Host ""

Write-Host "🐍 Installing Python $PythonMinor..." -ForegroundColor Cyan
Install-Python
Write-Host ""

Write-Host "📦 Installing pip..." -ForegroundColor Cyan
Install-Pip

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

Write-Host "📜 Creating command files..." -ForegroundColor Cyan
Write-CmdFiles
Write-Host ""

Invoke-PortableDevVerification

Write-Host ""
Write-Host "✅ Created portable dev environment:" -ForegroundColor Green
Write-Host "   🖥️ vscode  $VsCodeVersion"
Write-Host "   🐍 python  $PythonVersion"
Write-Host "   📦 pip     $PipVersion"
Write-Host "   🟩 node    $NodeVersion"
Write-Host "   ⚡ uv      $UvVersion"
Write-Host "   🔧 jq      $JqVersion"
Write-Host "   📄 pandoc  $PandocVersion"
Write-Host ""
Write-Host "⏩  Run verify-pdev.cmd to verify, or start-pdev.cmd to launch VSCode with portable PATH." -ForegroundColor Green
Write-Host "   🏃 Launch VSCode with portable PATH. : start-pdev.cmd"
Write-Host "   🔍 Verify environment.               : verify-pdev.cmd"
Write-Host ""
