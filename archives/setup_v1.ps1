<#
.SYNOPSIS
  Desktop 配下だけに Python / Node.js / pip / uv / jq / pandoc / VS Code / Cygwin をポータブル配置する。

.DESCRIPTION
  既定配置:
    %USERPROFILE%\Desktop\portable-dev\
      .local\opt\{python,nodejs,uv,jq,pandoc,vscode,cygwin}\  展開済みバイナリ
      .local\pkg\                                              ダウンロードキャッシュ
      .local\logs\                                             実行ログ
      .local\tmp\                                              一時展開先
      .config\                                                  設定・ユーザーデータ
      VSCode.bat                                                VS Code 起動コマンド
      Cygwin.bat                                                Cygwin 起動コマンド

.NOTES
  - 管理者権限不要を想定。
  - pip は get-pip.py ではなく pip wheel を PyPI から取得してインストールする。
  - Cygwin は公式 setup-x86_64.exe を CLI 実行する。Cygwin は rolling distribution のため、任意の過去バージョン固定は公式 setup だけでは保証しない。
  - Desktop 配下以外を指定した場合は停止する。
#>

[CmdletBinding()]
param(
  [string]$Root = [IO.Path]::Combine($env:USERPROFILE, 'Desktop', 'pdev'),

  # Python embeddable zip のバージョン
  # [string]$PythonVersion = '3.13.13',
  [string]$PythonVersion = '3.12.10',

  # Node.js Windows x64 zip のバージョン。v は付けても付けなくてもよい。
  [string]$NodeVersion = '24.16.0',

  # uv GitHub release のバージョン。v は付けても付けなくてもよい。
  [string]$UvVersion = '0.11.18',

  # jq GitHub release のバージョン。jq- は付けても付けなくてもよい。
  [string]$JqVersion = '1.8.0',

  # pandoc GitHub release のバージョン
  [string]$PandocVersion = '3.9.0.2',

  # VS Code archive の品質。stable / insiders を想定。
  [string]$VSCodeVersion = 'stable',

  # Cygwin は setup executable で最新パッケージを導入する。
  [string]$CygwinPackages = 'bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux',

  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
  # TLS 1.2 が未定義の環境では既定設定のまま続行する。
}

# --- パス定義 ---------------------------------------------------------------
$DesktopRoot = [Environment]::GetFolderPath('Desktop')
$Root = [IO.Path]::GetFullPath($Root)
$PkgDir = Join-Path $Root '.local/pkg'
$OptDir = Join-Path $Root '.local/opt'
$ConfigDir = Join-Path $Root '.config'
$LogDir = Join-Path $Root '.local/logs'
$TmpDir = Join-Path $Root '.local/tmp'
$LogFile = Join-Path $LogDir ('install-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
$CygwinSetupUrl = 'https://cygwin.com/setup-x86_64.exe'
$CygwinMirrors = @(
  'https://ftp.jaist.ac.jp/pub/cygwin/',
  'https://ftp.yamagata-u.ac.jp/pub/cygwin/',
  'https://ftp.iij.ad.jp/pub/cygwin/'
)
$CygwinFallbackMirror = 'https://mirrors.kernel.org/sourceware/cygwin/'
$VSCodeExtensions = @(
  'ZooCodeOrganization.zoo-code',
  'zhuangtongfa.Material-theme',
  'openai.chatgpt',
  'anthropic.claude-code'
)

# --- ログ関数 ---------------------------------------------------------------
function Write-Log {
  <#
  .SYNOPSIS
    色、時刻付きで進捗を表示し、ログファイルへ書き込みます。

  .PARAMETER Message
    出力するログメッセージです。

  .PARAMETER Level
    ログの種類です。
  #>
  param(
    [Parameter(Mandatory)] [string]$Message,
    [ValidateSet('INFO','OK','WARN','ERROR','STEP')] [string]$Level = 'INFO'
  )
  $stamp = Get-Date -Format 'HH:mm:ss'
  $map = @{
    INFO  = @{ Color='Cyan' }
    OK    = @{ Color='Green' }
    WARN  = @{ Color='Yellow' }
    ERROR = @{ Color='Red' }
    STEP  = @{ Color='Magenta' }
  }
  $line = "[$stamp] [$Level] $Message"
  Write-Host $line -ForegroundColor $map[$Level].Color
  if (Test-Path $LogDir) { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 }
}

function Assert-UnderDesktop {
  <#
  .SYNOPSIS
    指定されたパスが Desktop 配下にあることを検証します。

  .PARAMETER Path
    検証対象のパスです。
  #>
  param([Parameter(Mandatory)][string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $desktopFull = [IO.Path]::GetFullPath($DesktopRoot)
  if (-not $full.StartsWith($desktopFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The install root must be under Desktop: $full"
  }
}

function New-Directory {
  <#
  .SYNOPSIS
    存在しないディレクトリを作成します。

  .PARAMETER Path
    作成するディレクトリのパスです。
  #>
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Download-FileCached {
  <#
  .SYNOPSIS
    ファイルを .local/pkg にキャッシュしながらダウンロードします。

  .PARAMETER Url
    ダウンロード元 URL です。

  .PARAMETER FileName
    キャッシュに保存するファイル名です。

  .OUTPUTS
    ダウンロードまたはキャッシュ済みファイルのパスを返します。
  #>
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$FileName
  )
  $dest = Join-Path $PkgDir $FileName
  if ((Test-Path -LiteralPath $dest) -and (-not $Force)) {
    Write-Log "Using cached file: $FileName" 'OK'
    return $dest
  }
  Write-Log "Downloading: $Url" 'INFO'
  Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
  return $dest
}

function Download-FirstAvailableCached {
  <#
  .SYNOPSIS
    候補 URL のうち最初に取得できるファイルを .local/pkg にキャッシュします。

  .PARAMETER Candidates
    Url と FileName を含む候補オブジェクトの一覧です。

  .PARAMETER ErrorMessage
    すべての候補が取得できない場合に表示するエラーメッセージです。

  .OUTPUTS
    ダウンロードまたはキャッシュ済みファイルのパスを返します。
  #>
  param(
    [Parameter(Mandatory)][object[]]$Candidates,
    [Parameter(Mandatory)][string]$ErrorMessage
  )

  foreach ($candidate in $Candidates) {
    try {
      return Download-FileCached $candidate.Url $candidate.FileName
    } catch {
      Write-Log "Download candidate failed: $($candidate.Url) ($($_.Exception.Message))" 'WARN'
    }
  }

  throw $ErrorMessage
}

function Expand-ZipClean {
  <#
  .SYNOPSIS
    zip を展開し、単一ルートフォルダの場合は中身だけを配置します。

  .PARAMETER ZipPath
    展開する zip ファイルのパスです。

  .PARAMETER Destination
    展開先ディレクトリです。
  #>
  param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$Destination
  )
  $tmp = Join-Path $TmpDir ('portable-dev-' + [guid]::NewGuid().ToString('N'))
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  New-Directory $Destination
  New-Directory $tmp
  try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force
    $items = @(Get-ChildItem -LiteralPath $tmp)
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
      Copy-Item -Path (Join-Path $items[0].FullName '*') -Destination $Destination -Recurse -Force
    } else {
      Copy-Item -Path (Join-Path $tmp '*') -Destination $Destination -Recurse -Force
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-Checked {
  <#
  .SYNOPSIS
    外部コマンドを実行し、終了コードが 0 以外の場合に例外を送出します。

  .PARAMETER FilePath
    実行するファイルのパスです。

  .PARAMETER Arguments
    実行ファイルに渡す引数です。

  .PARAMETER WorkingDirectory
    実行時の作業ディレクトリです。
  #>
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory = $Root
  )
  Write-Log "Running: $FilePath $($Arguments -join ' ')" 'INFO'
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -Wait -PassThru -NoNewWindow
  if ($p.ExitCode -ne 0) { throw "Command failed with ExitCode=$($p.ExitCode): $FilePath" }
}

function Get-VersionTag {
  <#
  .SYNOPSIS
    バージョン文字列に v 接頭辞を付けたタグ形式へ整形します。

  .PARAMETER Version
    整形するバージョン文字列です。

  .OUTPUTS
    v 接頭辞付きのバージョンタグを返します。
  #>
  param([Parameter(Mandatory)][string]$Version)
  if ($Version.StartsWith('v')) { return $Version }
  return "v$Version"
}

function Install-PythonEmbedded {
  <#
  .SYNOPSIS
    Python embeddable zip を展開し、site-packages と pip 利用を有効化します。

  .PARAMETER Destination
    Python の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing Python $PythonVersion to: $Destination" 'STEP'
  $pyCompact = $PythonVersion.Replace('.', '')
  $zip = Download-FirstAvailableCached `
    -Candidates @(
      [pscustomobject]@{
        Url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
        FileName = "python-$PythonVersion-embed-amd64.zip"
      },
      [pscustomobject]@{
        Url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embeddable-amd64.zip"
        FileName = "python-$PythonVersion-embeddable-amd64.zip"
      }
    ) `
    -ErrorMessage "Could not find the Windows embeddable zip for Python $PythonVersion. Specify a version that provides python-$PythonVersion-embed-amd64.zip or python-$PythonVersion-embeddable-amd64.zip at https://www.python.org/ftp/python/$PythonVersion/."
  Expand-ZipClean $zip $Destination

  $pth = Get-ChildItem -LiteralPath $Destination -Filter 'python*._pth' | Select-Object -First 1
  if ($null -ne $pth) {
    # 日本語コメント: embeddable Python は既定で site import が無効なので pip 用に有効化する。
    $content = Get-Content -LiteralPath $pth.FullName -Raw
    $content = $content -replace '#import site', 'import site'
    Set-Content -LiteralPath $pth.FullName -Value $content -Encoding ASCII
  }

  New-Directory (Join-Path $ConfigDir 'pip')
  $pipIni = Join-Path $ConfigDir 'pip/pip.ini'
  Set-Content -LiteralPath $pipIni -Encoding ASCII -Value @"
[global]
disable-pip-version-check = true
"@
}

function Install-PipFromWheel {
  <#
  .SYNOPSIS
    PyPI JSON から最新 pip wheel を取得し、wheel から pip をインストールします。

  .PARAMETER PythonExe
    pip を導入する Python 実行ファイルのパスです。
  #>
  param([Parameter(Mandatory)][string]$PythonExe)
  Write-Log "Installing pip from wheel" 'STEP'
  $metaUrl = 'https://pypi.org/pypi/pip/json'
  $meta = Invoke-RestMethod -Uri $metaUrl
  $wheel = $meta.urls | Where-Object { $_.packagetype -eq 'bdist_wheel' -and $_.filename -like 'pip-*-py3-none-any.whl' } | Select-Object -First 1
  if ($null -eq $wheel) { throw 'Could not find a pip wheel.' }
  $pipWheel = Download-FileCached $wheel.url $wheel.filename
  $env:PIP_CACHE_DIR = Join-Path $PkgDir 'pip-cache'
  $code = @"
import sys
sys.path.insert(0, r'$pipWheel')
from pip._internal.cli.main import main
raise SystemExit(main(['install', '--no-index', '--no-warn-script-location', '--force-reinstall', r'$pipWheel']))
"@
  & $PythonExe -c $code
  if ($LASTEXITCODE -ne 0) { throw "pip wheel installation failed. ExitCode=$LASTEXITCODE" }
}

function Install-NodeZip {
  <#
  .SYNOPSIS
    Node.js 公式 Windows x64 zip を展開します。

  .PARAMETER Destination
    Node.js の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing Node.js $NodeVersion to: $Destination" 'STEP'
  $tag = Get-VersionTag $NodeVersion
  $url = "https://nodejs.org/dist/$tag/node-$tag-win-x64.zip"
  $zip = Download-FileCached $url "node-$tag-win-x64.zip"
  Expand-ZipClean $zip $Destination
}

function Install-UvZip {
  <#
  .SYNOPSIS
    uv の Windows x86_64 MSVC zip を展開します。

  .PARAMETER Destination
    uv の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing uv $UvVersion to: $Destination" 'STEP'
  $version = $UvVersion.TrimStart('v')
  $url = "https://releases.astral.sh/github/uv/releases/download/$version/uv-x86_64-pc-windows-msvc.zip"
  $zip = Download-FileCached $url "uv-$version-x86_64-pc-windows-msvc.zip"
  Expand-ZipClean $zip $Destination
}

function Install-JqExe {
  <#
  .SYNOPSIS
    jq の単体 exe を配置し、jq.exe 名に正規化します。

  .PARAMETER Destination
    jq の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing jq $JqVersion to: $Destination" 'STEP'
  New-Directory $Destination
  $tag = if ($JqVersion.StartsWith('jq-')) { $JqVersion } else { "jq-$JqVersion" }
  $exe = Download-FileCached "https://github.com/jqlang/jq/releases/download/$tag/jq-windows-amd64.exe" "jq-$JqVersion-windows-amd64.exe"
  Copy-Item -LiteralPath $exe -Destination (Join-Path $Destination 'jq.exe') -Force
}

function Install-PandocZip {
  <#
  .SYNOPSIS
    pandoc の Windows x86_64 zip を展開します。

  .PARAMETER Destination
    pandoc の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing pandoc $PandocVersion to: $Destination" 'STEP'
  $url = "https://github.com/jgm/pandoc/releases/download/$PandocVersion/pandoc-$PandocVersion-windows-x86_64.zip"
  $zip = Download-FileCached $url "pandoc-$PandocVersion-windows-x86_64.zip"
  Expand-ZipClean $zip $Destination
}

function Install-VSCodeZip {
  <#
  .SYNOPSIS
    VS Code zip を展開し、data フォルダで portable mode を有効化します。

  .PARAMETER Destination
    VS Code の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing VS Code $VSCodeVersion to: $Destination" 'STEP'
  $versionSegment = if ($VSCodeVersion -in @('stable','latest')) { 'latest' } else { $VSCodeVersion }
  $url = "https://update.code.visualstudio.com/$versionSegment/win32-x64-archive/stable"
  $zip = Download-FileCached $url "vscode-$versionSegment-win32-x64-archive.zip"
  Expand-ZipClean $zip $Destination
  New-Directory (Join-Path $Destination 'data')
  New-Directory (Join-Path $Destination 'data/user-data/User')
  New-Directory (Join-Path $Destination 'data/extensions')
}

function Test-CygwinMirror {
  <#
  .SYNOPSIS
    Cygwin mirror の setup メタデータへ到達できるか確認します。

  .PARAMETER Mirror
    確認対象の Cygwin mirror URL です。

  .OUTPUTS
    到達できる場合は True、到達できない場合は False を返します。
  #>
  param([Parameter(Mandatory)][string]$Mirror)

  $metadataUrl = ($Mirror.TrimEnd('/') + '/x86_64/setup.xz')
  try {
    Invoke-WebRequest -Uri $metadataUrl -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
    return $true
  } catch {
    Write-Log "Cygwin mirror is unreachable: $Mirror ($($_.Exception.Message))" 'WARN'
    return $false
  }
}

function Select-CygwinMirror {
  <#
  .SYNOPSIS
    国内 Cygwin mirror を優先し、全滅時に fallback mirror を選択します。

  .OUTPUTS
    選択した Cygwin mirror URL を返します。
  #>
  foreach ($mirror in $CygwinMirrors) {
    if (Test-CygwinMirror $mirror) {
      return $mirror
    }
  }

  Write-Log "No preferred Cygwin mirror is reachable; using fallback: $CygwinFallbackMirror" 'WARN'
  return $CygwinFallbackMirror
}

function Write-CygwinSetupDefaults {
  <#
  .SYNOPSIS
    Cygwin setup が現在ユーザ向け、システムプロキシ設定で動くよう既定設定を書き込みます。

  .PARAMETER Destination
    Cygwin の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)

  $setupDir = Join-Path $Destination 'etc/setup'
  New-Directory $setupDir

  # 日本語コメント: setup の旧 IE5 method は現在の "Use System Proxy Settings" 相当として扱われる。
  Set-Content -LiteralPath (Join-Path $setupDir 'net-method') -Value 'IE5' -Encoding ASCII
}

function Install-Cygwin {
  <#
  .SYNOPSIS
    Cygwin setup をサイレント実行し、Root 配下へ Cygwin を配置します。

  .PARAMETER Destination
    Cygwin の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$Destination)
  Write-Log "Installing Cygwin to: $Destination" 'STEP'
  New-Directory $Destination
  $setup = Download-FileCached $CygwinSetupUrl 'setup-x86_64.exe'
  $localPkg = Join-Path $PkgDir 'cygwin'
  New-Directory $localPkg
  Write-CygwinSetupDefaults $Destination
  $mirror = Select-CygwinMirror
  Write-Log "Cygwin mirror: $mirror" 'INFO'
  $args = @(
    '--quiet-mode',
    '--no-admin',
    '--only-site',
    '--root', $Destination,
    '--local-package-dir', $localPkg,
    '--site', $mirror,
    '--packages', $CygwinPackages
  )
  Invoke-Checked -FilePath $setup -Arguments $args
}

function Write-VSCodeSettings {
  <#
  .SYNOPSIS
    VS Code integrated terminal から Cygwin bash を呼び出す settings.json を生成します。

  .PARAMETER VSCodeDir
    VS Code の配置先ディレクトリです。

  .PARAMETER CygwinDir
    Cygwin の配置先ディレクトリです。

  .PARAMETER PathEntries
    VS Code terminal に渡す PATH エントリです。
  #>
  param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string[]]$PathEntries
  )
  $settingsPath = Join-Path $VSCodeDir 'data/user-data/User/settings.json'
  $bash = (Join-Path $CygwinDir 'bin/bash.exe').Replace('\','\\')
  $envPath = ($PathEntries -join ';').Replace('\','\\')
  $settings = [ordered]@{
    'terminal.integrated.defaultProfile.windows' = 'PowerShell-Portable'
    'terminal.integrated.profiles.windows' = [ordered]@{
      'Cygwin' = [ordered]@{
        path = (Join-Path $CygwinDir 'bin/bash.exe')
        args = @('--login','-i')
        icon = 'terminal-bash'
        env = [ordered]@{
          CHERE_INVOKING = '1'
          PATH = "${envPath};`${env:PATH}"
        }
      }
      'PowerShell-Portable' = [ordered]@{
        path = 'powershell.exe'
        args = @('-NoLogo')
        env = [ordered]@{ PATH = "${envPath};`${env:PATH}" }
      }
    }
    'terminal.integrated.env.windows' = [ordered]@{
      PATH = "${envPath};`${env:PATH}"
      PIP_CONFIG_FILE = (Join-Path $ConfigDir 'pip/pip.ini')
      PIP_CACHE_DIR = (Join-Path $PkgDir 'pip-cache')
      UV_CACHE_DIR = (Join-Path $PkgDir 'uv-cache')
      npm_config_cache = (Join-Path $PkgDir 'npm-cache')
    }
    'workbench.colorTheme' = 'Visual Studio Dark'
    'window.commandCenter' = $false
    'chat.titleBar.signIn.enabled' = $false
    'chat.disableAIFeatures' = $true
  }
  $json = $settings | ConvertTo-Json -Depth 20
  Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
}

function Write-VSCodeExtensionRecommendations {
  <#
  .SYNOPSIS
    VS Code が推奨拡張として表示する extensions.json を user-data 配下に生成します。

  .PARAMETER VSCodeDir
    VS Code の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$VSCodeDir)

  $extensionsPath = Join-Path $VSCodeDir 'data/user-data/User/extensions.json'
  $extensions = [ordered]@{
    recommendations = $VSCodeExtensions
  }
  $json = $extensions | ConvertTo-Json -Depth 10
  Set-Content -LiteralPath $extensionsPath -Value $json -Encoding UTF8
}

function Install-VSCodeExtensions {
  <#
  .SYNOPSIS
    VS Code CLI を使って portable extensions dir に拡張機能をインストールします。

  .PARAMETER VSCodeDir
    VS Code の配置先ディレクトリです。
  #>
  param([Parameter(Mandatory)][string]$VSCodeDir)

  $codeCmd = Join-Path $VSCodeDir 'bin/code.cmd'
  $userDataDir = Join-Path $VSCodeDir 'data/user-data'
  $extensionsDir = Join-Path $VSCodeDir 'data/extensions'

  foreach ($extensionId in $VSCodeExtensions) {
    Write-Log "Installing VS Code extension: $extensionId" 'STEP'
    Invoke-Checked -FilePath $codeCmd -Arguments @(
      '--user-data-dir', $userDataDir,
      '--extensions-dir', $extensionsDir,
      '--install-extension', $extensionId,
      '--force'
    )
  }
}

function Get-CmdSafePath {
  <#
  .SYNOPSIS
    cmd.exe から外部プロセスへ渡しても文字化けしにくい短いパスを返します。

  .PARAMETER Path
    短いパスへ変換する既存パスです。
  #>
  param([Parameter(Mandatory)][string]$Path)

  try {
    $resolved = [IO.Path]::GetFullPath($Path)
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $item = if (Test-Path -LiteralPath $resolved -PathType Container) {
      $fso.GetFolder($resolved)
    } else {
      $fso.GetFile($resolved)
    }
    if ($item.ShortPath -and ($item.ShortPath -cmatch '^[\x00-\x7F]+$')) {
      return $item.ShortPath
    }
  } catch {
    Write-Log "Could not get a short path; using the normal path: $Path ($($_.Exception.Message))" 'WARN'
  }

  return [IO.Path]::GetFullPath($Path)
}

function Write-Launchers {
  <#
  .SYNOPSIS
    Root 直下に VSCode.bat と Cygwin.bat を生成します。

  .PARAMETER VSCodeDir
    VS Code の配置先ディレクトリです。

  .PARAMETER PathEntries
    ランチャーに設定する PATH エントリです。
  #>
  param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string[]]$PathEntries
  )
  $vscodeBat = Join-Path $Root 'VSCode.bat'
  $cygwinBat = Join-Path $Root 'Cygwin.bat'
  $launcherRoot = Get-CmdSafePath $Root
  $vscode = @"
@echo off
setlocal enableextensions
set "ROOT=$launcherRoot"
set "PATH=%ROOT%\.local\opt\python;%ROOT%\.local\opt\python\Scripts;%ROOT%\.local\opt\nodejs;%ROOT%\.local\opt\uv;%ROOT%\.local\opt\jq;%ROOT%\.local\opt\pandoc;%ROOT%\.local\opt\vscode\bin;%PATH%"
set "PIP_CONFIG_FILE=%ROOT%\.config\pip\pip.ini"
set "PIP_CACHE_DIR=%ROOT%\.local\pkg\pip-cache"
set "UV_CACHE_DIR=%ROOT%\.local\pkg\uv-cache"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "CODE=%ROOT%\.local\opt\vscode\Code.exe"
set "VSCODE_USER_DATA=%ROOT%\.local\opt\vscode\data\user-data"
set "VSCODE_EXTENSIONS=%ROOT%\.local\opt\vscode\data\extensions"
set "CODEX_HOME=%ROOT%\.config\codex"
set "CODEX_SQLITE_HOME=%ROOT%\.cache\codex"
set "LITELLM_API_KEY=sk-litellm-master-key"

start "" /min "%CODE%" ^
    --user-data-dir "%VSCODE_USER_DATA%" ^
    --extensions-dir "%VSCODE_EXTENSIONS%" ^
    --disable-gpu ^
    --no-sandbox ^
    %ROOT%
endlocal
exit /b 0
"@
  $cygwin = @"
@echo off
setlocal enableextensions
set TERM=
cd /d "$launcherRoot\.local\opt\cygwin\bin" && .\bash --login -i
"@
  Set-Content -LiteralPath $vscodeBat -Value $vscode -Encoding ASCII
  Set-Content -LiteralPath $cygwinBat -Value $cygwin -Encoding ASCII
}

function Test-CommandPath {
  <#
  .SYNOPSIS
    対象ツールが PATH から見つかることを検証し、バージョンを表示します。

  .PARAMETER Name
    ログに表示するツール名です。

  .PARAMETER Exe
    PATH から検索する実行ファイル名です。

  .PARAMETER VersionArgs
    バージョン確認に渡す引数です。
  #>
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Exe,
    [string[]]$VersionArgs = @('--version')
  )
  $found = Get-Command $Exe -ErrorAction SilentlyContinue
  if ($null -eq $found) { throw "$Name was not found on PATH: $Exe" }
  Write-Log "$Name PATH OK: $($found.Source)" 'OK'
  try {
    $ver = & $Exe @VersionArgs 2>&1 | Select-Object -First 3
    Write-Log ("$Name version: " + (($ver -join ' ') -replace '\s+', ' ')) 'OK'
  } catch {
    Write-Log "$Name version check failed: $($_.Exception.Message)" 'WARN'
  }
}

try {
  Assert-UnderDesktop $Root
  foreach ($d in @($Root,$PkgDir,$OptDir,$ConfigDir,$LogDir,$TmpDir)) { New-Directory $d }
  Write-Log "Root: $Root" 'STEP'
  Write-Log "Log file: $LogFile" 'INFO'

  $PythonDir = Join-Path $OptDir 'python'
  $NodeDir   = Join-Path $OptDir 'nodejs'
  $UvDir     = Join-Path $OptDir 'uv'
  $JqDir     = Join-Path $OptDir 'jq'
  $PandocDir = Join-Path $OptDir 'pandoc'
  $VSCodeDir = Join-Path $OptDir 'vscode'
  $CygwinDir = Join-Path $OptDir 'cygwin'

  foreach ($p in @($PythonDir,$NodeDir,$UvDir,$JqDir,$PandocDir,$VSCodeDir,$CygwinDir)) { Assert-UnderDesktop $p }

  Install-PythonEmbedded $PythonDir
  $PythonExe = Join-Path $PythonDir 'python.exe'
  Install-PipFromWheel $PythonExe
  Install-NodeZip $NodeDir
  Install-UvZip $UvDir
  Install-JqExe $JqDir
  Install-PandocZip $PandocDir
  Install-VSCodeZip $VSCodeDir
  Install-Cygwin $CygwinDir

  $PathEntries = @(
    $PythonDir,
    (Join-Path $PythonDir 'Scripts'),
    $NodeDir,
    $UvDir,
    $JqDir,
    $PandocDir,
    (Join-Path $VSCodeDir 'bin'),
    (Join-Path $CygwinDir 'bin')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  # 日本語コメント: 現プロセス PATH に反映し、この後の検証と VS Code 起動に使う。
  $env:PATH = ($PathEntries -join ';') + ';' + $env:PATH
  $env:PIP_CONFIG_FILE = Join-Path $ConfigDir 'pip/pip.ini'
  $env:PIP_CACHE_DIR = Join-Path $PkgDir 'pip-cache'
  $env:UV_CACHE_DIR = Join-Path $PkgDir 'uv-cache'
  $env:npm_config_cache = Join-Path $PkgDir 'npm-cache'

  Write-VSCodeSettings -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -PathEntries $PathEntries
  Write-VSCodeExtensionRecommendations -VSCodeDir $VSCodeDir
  Install-VSCodeExtensions -VSCodeDir $VSCodeDir
  Write-Launchers -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -PathEntries $PathEntries

  Test-CommandPath 'python' 'python.exe' @('--version')
  Test-CommandPath 'pip' 'pip.exe' @('--version')
  Test-CommandPath 'node' 'node.exe' @('--version')
  Test-CommandPath 'npm' 'npm.cmd' @('--version')
  Test-CommandPath 'uv' 'uv.exe' @('--version')
  Test-CommandPath 'jq' 'jq.exe' @('--version')
  Test-CommandPath 'pandoc' 'pandoc.exe' @('--version')
  Test-CommandPath 'code' 'code.cmd' @('--version')
  Test-CommandPath 'cygwin bash' 'bash.exe' @('--version')

  Write-Log "VSCode launcher: $(Join-Path $Root 'VSCode.bat')" 'STEP'
  Write-Log "Cygwin launcher: $(Join-Path $Root 'Cygwin.bat')" 'STEP'
  Write-Log "Installation completed" 'OK'

} catch {
  Write-Log $_.Exception.Message 'ERROR'
  Write-Log "Log file: $LogFile" 'ERROR'
  throw
}
