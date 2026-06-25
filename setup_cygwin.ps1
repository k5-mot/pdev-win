
[CmdletBinding()]
param(
  [string]$Root = '',

  [string]$Packages = 'bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux,jq',

  [switch]$Force
)

$script:InstallForce = [bool]$Force

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
}

$DesktopRoot = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($DesktopRoot)) {
  throw 'Could not resolve the Desktop folder with Known Folder API.'
}
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = $DesktopRoot
}
$Root = [IO.Path]::GetFullPath($Root)
$PkgDir = Join-Path $Root '.local/pkg'
$OptDir = Join-Path $Root '.local/opt'
$DataDir = Join-Path $Root '.local/data'
$LogDir = Join-Path $Root '.local/logs'
$TmpDir = Join-Path $Root '.local/tmp'
$LogFile = Join-Path $LogDir ('install-cygwin-{0:yyyyMMdd-HHmmss-fffffff}-{1}.log' -f (Get-Date), $PID)
$CygwinSetupUrl = 'https://cygwin.com/setup-x86_64.exe'
$CygwinMirrors = @(
  'https://ftp.jaist.ac.jp/pub/cygwin/',
  'https://ftp.yamagata-u.ac.jp/pub/cygwin/',
  'https://ftp.iij.ad.jp/pub/cygwin/'
)
$CygwinFallbackMirror = 'https://mirrors.kernel.org/sourceware/cygwin/'

<#
.SYNOPSIS
ログメッセージをコンソールとログファイルへ出力します。
.PARAMETER Message
出力するメッセージです。
.PARAMETER Level
ログレベルです。
.PARAMETER LogOnly
コンソールへ表示せずログファイルのみに出力します。
#>
function Write-Log {
    param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO','OK','WARN','ERROR','STEP')][string]$Level = 'INFO',
    [switch]$LogOnly
  )

  $stamp = Get-Date -Format 'HH:mm:ss'
  $map = @{
    INFO  = @{ Color = 'Cyan' }
    OK    = @{ Color = 'Green' }
    WARN  = @{ Color = 'Yellow' }
    ERROR = @{ Color = 'Red' }
    STEP  = @{ Color = 'Magenta' }
  }
  $line = "[$stamp] [$Level] $Message"
  if (-not $LogOnly) {
    Write-Host $line -ForegroundColor $map[$Level].Color
  }
  try {
    if (Test-Path -LiteralPath $LogDir) {
      Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
  } catch {
  }
}

<#
.SYNOPSIS
指定されたパスが Desktop 配下であることを検証します。
.PARAMETER Path
検証するパスです。
#>
function Assert-UnderDesktop {
    param([Parameter(Mandatory)][string]$Path)

  $full = [IO.Path]::GetFullPath($Path)
  $desktopFull = [IO.Path]::GetFullPath($DesktopRoot)
  if (-not $full.StartsWith($desktopFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The install root must be under Desktop: $full"
  }
}

<#
.SYNOPSIS
指定されたディレクトリを必要に応じて作成します。
.PARAMETER Path
作成するディレクトリのパスです。
#>
function New-Directory {
    param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

<#
.SYNOPSIS
URL からファイルをダウンロードし、キャッシュ済みの場合は再利用します。
.PARAMETER Url
ダウンロード元 URL です。
.PARAMETER FileName
キャッシュ保存するファイル名です。
#>
function Download-FileCached {
    param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$FileName
  )

  $dest = Join-Path $PkgDir $FileName
  if ((Test-Path -LiteralPath $dest) -and (-not $script:InstallForce)) {
    Write-Log "Using cached file: $FileName" 'OK'
    return $dest
  }

  Write-Log "Downloading: $Url" 'INFO'
  Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
  return $dest
}

<#
.SYNOPSIS
外部コマンドを実行し、終了コードを検証します。
.PARAMETER FilePath
実行するファイルのパスです。
.PARAMETER Arguments
コマンド引数です。
.PARAMETER WorkingDirectory
実行時の作業ディレクトリです。
.PARAMETER LogOnly
標準出力と標準エラーをログファイルのみに記録します。
#>
function Invoke-Checked {
    param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory = $Root,
    [switch]$LogOnly
  )

  Write-Log "Running: $FilePath $($Arguments -join ' ')" 'INFO' -LogOnly:$LogOnly
  if (-not $LogOnly) {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "Command failed with ExitCode=$($p.ExitCode): $FilePath" }
    return
  }

  $stdout = Join-Path $TmpDir ('process-{0}-stdout.log' -f [guid]::NewGuid().ToString('N'))
  $stderr = Join-Path $TmpDir ('process-{0}-stderr.log' -f [guid]::NewGuid().ToString('N'))
  try {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    foreach ($path in @($stdout, $stderr)) {
      if (Test-Path -LiteralPath $path) {
        $content = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
        if ($content) {
          Add-Content -LiteralPath $LogFile -Value $content -Encoding UTF8 -ErrorAction SilentlyContinue
        }
      }
    }
    if ($p.ExitCode -ne 0) { throw "Command failed with ExitCode=$($p.ExitCode): $FilePath" }
  } finally {
    Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
  }
}

<#
.SYNOPSIS
Cygwin mirror の metadata にアクセスできるか確認します。
.PARAMETER Mirror
確認する Cygwin mirror URL です。
#>
function Test-CygwinMirror {
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

<#
.SYNOPSIS
利用可能な Cygwin mirror を選択します。
#>
function Select-CygwinMirror {
  foreach ($mirror in $CygwinMirrors) {
    if (Test-CygwinMirror $mirror) {
      return $mirror
    }
  }

  Write-Log "No preferred Cygwin mirror is reachable; using fallback: $CygwinFallbackMirror" 'WARN'
  return $CygwinFallbackMirror
}

<#
.SYNOPSIS
Cygwin setup の既定設定ファイルを作成します。
.PARAMETER Destination
Cygwin のインストール先ディレクトリです。
#>
function Write-CygwinSetupDefaults {
    param([Parameter(Mandatory)][string]$Destination)

  $setupDir = Join-Path $Destination 'etc/setup'
  New-Directory $setupDir
  Set-Content -LiteralPath (Join-Path $setupDir 'net-method') -Value 'IE5' -Encoding ASCII
}

<#
.SYNOPSIS
Cygwin setup を実行して Cygwin をインストールします。
.PARAMETER Destination
Cygwin のインストール先ディレクトリです。
.PARAMETER Packages
インストールする Cygwin パッケージ一覧です。
#>
function Install-Cygwin {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Packages
  )

  Write-Log "Installing Cygwin to: $Destination" 'STEP' -LogOnly
  New-Directory $Destination
  $setup = Download-FileCached $CygwinSetupUrl 'setup-x86_64.exe'
  $localPkg = Join-Path $DataDir 'cygwin'
  New-Directory $localPkg
  Write-CygwinSetupDefaults $Destination
  $mirror = Select-CygwinMirror
  Write-Log "Cygwin mirror: $mirror" 'INFO' -LogOnly
  $cygwinArgs = @(
    '--quiet-mode',
    '--no-admin',
    '--only-site',
    '--root', $Destination,
    '--local-package-dir', $localPkg,
    '--site', $mirror,
    '--packages', $Packages
  )
  Invoke-Checked -FilePath $setup -Arguments $cygwinArgs -LogOnly
}

<#
.SYNOPSIS
cmd launcher から扱いやすいパス表現を取得します。
.PARAMETER Path
変換するパスです。
#>
function Get-CmdSafePath {
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

<#
.SYNOPSIS
Root 直下に Cygwin launcher を生成します。
.PARAMETER CygwinDir
Cygwin のインストール先ディレクトリです。
#>
function Write-CygwinLauncher {
    param([Parameter(Mandatory)][string]$CygwinDir)

  $cygwinCmd = Join-Path $Root 'Cygwin.cmd'
  $launcherRoot = Get-CmdSafePath $Root
  $cygwin = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set "CYGWIN_ROOT=%ROOT%\.local\opt\cygwin"
set "CYGWIN_PACKAGE_CACHE=%ROOT%\.local\data\cygwin"
set TERM=
set "PATH=%ROOT%\.local\opt\cygwin\bin"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
cd /d "%ROOT%\.local\opt\cygwin\bin" && .\bash --login -i
popd
"@
  Set-Content -LiteralPath $cygwinCmd -Value $cygwin -Encoding ASCII
}

<#
.SYNOPSIS
JSON オブジェクトへプロパティを追加または更新します。
.PARAMETER Object
更新する JSON 由来のオブジェクトです。
.PARAMETER Name
プロパティ名です。
.PARAMETER Value
設定する値です。
#>
function Set-JsonObjectProperty {
    param(
    [Parameter(Mandatory)][object]$Object,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][object]$Value
  )

  $property = $Object.PSObject.Properties[$Name]
  if ($null -ne $property) {
    $property.Value = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

<#
.SYNOPSIS
VS Code portable settings に Cygwin terminal profile を追加します。
.PARAMETER VSCodeDir
VS Code のインストール先ディレクトリです。
.PARAMETER CygwinDir
Cygwin のインストール先ディレクトリです。
#>
function Update-VSCodeCygwinProfile {
    param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir
  )

  $settingsPath = Join-Path $VSCodeDir 'data/user-data/User/settings.json'
  if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Log "VS Code settings were not found; skipping Cygwin terminal profile: $settingsPath" 'WARN'
    return
  }

  $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
  $profiles = $settings.PSObject.Properties['terminal.integrated.profiles.windows']
  if ($null -eq $profiles -or $null -eq $profiles.Value) {
    $profilesValue = [pscustomobject]([ordered]@{})
    Set-JsonObjectProperty -Object $settings -Name 'terminal.integrated.profiles.windows' -Value $profilesValue
  } else {
    $profilesValue = $profiles.Value
  }

  $cygwinPath = (Join-Path $CygwinDir 'bin/bash.exe')
  $cygwinEnvPath = (Join-Path $CygwinDir 'bin').Replace('\','\\')
  $profile = [pscustomobject]([ordered]@{
    path = $cygwinPath
    args = @('--login','-i')
    icon = 'terminal-bash'
    env = [pscustomobject]([ordered]@{
      CHERE_INVOKING = '1'
      PATH = $cygwinEnvPath
    })
  })
  Set-JsonObjectProperty -Object $profilesValue -Name 'Cygwin' -Value $profile
  $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

<#
.SYNOPSIS
指定された実行ファイルの存在とバージョンコマンドを確認します。
.PARAMETER Name
ログに表示するツール名です。
.PARAMETER FilePath
確認する実行ファイルのパスです。
.PARAMETER VersionArgs
バージョン確認に使う引数です。
#>
function Test-CommandFile {
    param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$VersionArgs = @('--version')
  )

  if (-not (Test-Path -LiteralPath $FilePath)) { throw "$Name was not found: $FilePath" }
  Write-Log "$Name path OK: $FilePath" 'OK'
  try {
    $ver = & $FilePath @VersionArgs 2>&1 | Select-Object -First 3
    Write-Log ("$Name version: " + (($ver -join ' ') -replace '\s+', ' ')) 'OK'
  } catch {
    Write-Log "$Name version check failed: $($_.Exception.Message)" 'WARN'
  }
}

try {
  Assert-UnderDesktop $Root
  foreach ($d in @($Root,$PkgDir,$OptDir,$DataDir,$LogDir,$TmpDir)) { New-Directory $d }
  $env:TEMP = $TmpDir
  $env:TMP = $TmpDir
  Write-Log "Root: $Root" 'STEP'
  Write-Log "Log file: $LogFile" 'INFO'
  Write-Log "TEMP/TMP: $TmpDir" 'INFO'

  $CygwinDir = Join-Path $OptDir 'cygwin'
  $VSCodeDir = Join-Path $OptDir 'vscode'
  Assert-UnderDesktop $CygwinDir

  Install-Cygwin -Destination $CygwinDir -Packages $Packages
  Write-CygwinLauncher -CygwinDir $CygwinDir
  Update-VSCodeCygwinProfile -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir

  $BashExe = Join-Path $CygwinDir 'bin/bash.exe'
  Test-CommandFile 'cygwin bash' $BashExe @('--version')

  Write-Log "Cygwin launcher: $(Join-Path $Root 'Cygwin.cmd')" 'STEP'
  Write-Log "Cygwin installation completed" 'OK'
} catch {
  Write-Log $_.Exception.Message 'ERROR'
  Write-Log "Log file: $LogFile" 'ERROR'
  throw
}
