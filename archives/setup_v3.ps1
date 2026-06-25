<#
.SYNOPSIS
  Desktop 配下だけに Python / Node.js / pip / uv / jq / pandoc / Rust / VS Code / Cygwin をポータブル配置する。

.DESCRIPTION
  既定配置:
    [Environment]::GetFolderPath('Desktop')\pdev\
      .local\opt\{python,nodejs,uv,jq,pandoc,rustup,cargo,vscode,cygwin}\  展開済みバイナリ
      .local\pkg\                                              ダウンロードキャッシュ
      .local\logs\                                             実行ログ
      .local\tmp\                                              一時展開先
      .config\                                                  設定・ユーザーデータ
      VSCode.bat                                                VS Code 起動コマンド
      Cygwin.bat                                                Cygwin 起動コマンド

.NOTES
  - 管理者権限不要を想定。
  - pip は get-pip.py / pip install ではなく、PyPI の最新 pip wheel を site-packages へ直接展開する。
  - pip.exe は使わず、Scripts\pip.cmd から python -m pip を呼び出す。
  - Cygwin は公式 setup-x86_64.exe を CLI 実行する。Cygwin は rolling distribution のため、任意の過去バージョン固定は公式 setup だけでは保証しない。
  - Rust は rustup-init.exe を使って RUSTUP_HOME / CARGO_HOME をポータブルディレクトリへ向けてインストールする。
  - Desktop 配下以外を指定した場合は停止する。Desktop は Known Folder API で取得する。
#>

[CmdletBinding()]
param(
  [string]$Root = '',

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

  # Rust ツールチェーンバージョン。stable / beta / nightly または 1.xx.y 形式。
  [string]$RustVersion = 'stable',

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
if ([string]::IsNullOrWhiteSpace($DesktopRoot)) {
  throw 'Could not resolve the Desktop folder with Known Folder API.'
}
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = [IO.Path]::Combine($DesktopRoot, 'pdev')
}
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

function Test-NetworkPath {
  <#
  .SYNOPSIS
    指定されたパスが UNC またはネットワークドライブ上にあるかを判定します。

  .PARAMETER Path
    判定対象のパスです。

  .OUTPUTS
    ネットワークパスの場合は True、それ以外は False を返します。
  #>
  param([Parameter(Mandatory)][string]$Path)

  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\', [StringComparison]::Ordinal)) {
    return $true
  }

  try {
    $rootName = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    $driveName = $rootName.TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    return ($null -ne $drive -and $drive.DisplayRoot)
  } catch {
    return $false
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
    Python embeddable zip を展開し、site-packages と site import を有効化します。

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
  New-Directory (Join-Path $Destination 'Lib/site-packages')

  $pth = Get-ChildItem -LiteralPath $Destination -Filter 'python*._pth' | Select-Object -First 1
  if ($null -ne $pth) {
    # 日本語コメント: embeddable Python は _pth が sys.path を固定するため site-packages を明示する。
    $pthLines = @()
    $pthLines = @([System.IO.File]::ReadAllLines($pth.FullName))
    $updated = New-Object 'System.Collections.Generic.List[string]'
    $hasSitePackages = $false
    $hasImportSite = $false

    foreach ($line in $pthLines) {
      $normalized = $line.Trim() -replace '/', '\'
      if ($normalized -ieq 'Lib\site-packages') { $hasSitePackages = $true }
      if ($normalized -ieq 'import site') { $hasImportSite = $true }
      if ($normalized -ieq '#import site') {
        if (-not $hasSitePackages) {
          $updated.Add('Lib\site-packages') | Out-Null
          $hasSitePackages = $true
        }
        $updated.Add('import site') | Out-Null
        $hasImportSite = $true
      } else {
        $updated.Add($line) | Out-Null
      }
    }

    if (-not $hasSitePackages) { $updated.Add('Lib\site-packages') | Out-Null }
    if (-not $hasImportSite) { $updated.Add('import site') | Out-Null }
    Set-Content -LiteralPath $pth.FullName -Value $updated.ToArray() -Encoding ASCII
  }

  New-Directory (Join-Path $ConfigDir 'pip')
  $pipIni = Join-Path $ConfigDir 'pip/pip.ini'
  Set-Content -LiteralPath $pipIni -Encoding ASCII -Value @"
[global]
disable-pip-version-check = true
no-build-isolation = true
"@
}

function Install-PipFromWheel {
  <#
  .SYNOPSIS
    PyPI JSON から最新 pip wheel を取得し、site-packages へ直接展開します。

  .PARAMETER PythonExe
    pip を導入する Python 実行ファイルのパスです。
  #>
  param([Parameter(Mandatory)][string]$PythonExe)
  Write-Log "Installing latest pip wheel into site-packages" 'STEP'
  $metaUrl = 'https://pypi.org/pypi/pip/json'
  $meta = Invoke-RestMethod -Uri $metaUrl
  $wheel = $meta.urls | Where-Object { $_.packagetype -eq 'bdist_wheel' -and $_.filename -like 'pip-*-py3-none-any.whl' } | Select-Object -First 1
  if ($null -eq $wheel) { throw 'Could not find a pip wheel.' }
  $pipWheel = Download-FileCached $wheel.url $wheel.filename

  $pythonDir = Split-Path -Parent $PythonExe
  $sitePackages = Join-Path $pythonDir 'Lib/site-packages'
  $scriptsDir = Join-Path $pythonDir 'Scripts'
  New-Directory $sitePackages
  New-Directory $scriptsDir

  Get-ChildItem -LiteralPath $sitePackages -Filter 'pip*' -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'pip' -or $_.Name -like 'pip-*.dist-info' } |
    Remove-Item -Recurse -Force

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($pipWheel, $sitePackages)

  $pipCmd = Join-Path $scriptsDir 'pip.cmd'
  $pipCmdBody = @"
@echo off
setlocal
set "PYTHON_EXE=%~dp0..\python.exe"
"%PYTHON_EXE%" -m pip %*
exit /b %ERRORLEVEL%
"@
  Set-Content -LiteralPath $pipCmd -Value $pipCmdBody -Encoding ASCII

  & $PythonExe -m pip --version
  if ($LASTEXITCODE -ne 0) { throw "pip wheel direct extraction failed. ExitCode=$LASTEXITCODE" }
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

function Install-Rust {
  <#
  .SYNOPSIS
    rustup-init.exe を使って Rust をポータブルディレクトリへインストールします。
    RUSTUP_HOME にツールチェーン、CARGO_HOME にカーゴバイナリを配置します。

  .PARAMETER RustupDestination
    rustup ツールチェーンの配置先ディレクトリ (RUSTUP_HOME) です。

  .PARAMETER CargoDestination
    Cargo バイナリ・レジストリの配置先ディレクトリ (CARGO_HOME) です。
  #>
  param(
    [Parameter(Mandatory)][string]$RustupDestination,
    [Parameter(Mandatory)][string]$CargoDestination
  )
  Write-Log "Installing Rust ($RustVersion) to: $CargoDestination" 'STEP'
  New-Directory $RustupDestination
  New-Directory $CargoDestination

  $rustupInit = Download-FileCached `
    'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' `
    'rustup-init.exe'

  # RUSTUP_HOME / CARGO_HOME をポータブルパスへ向けてから rustup-init を実行する。
  $env:RUSTUP_HOME = $RustupDestination
  $env:CARGO_HOME  = $CargoDestination

  $toolchain = $RustVersion.TrimStart('v')
  $rustupArgs = @(
    '-y',
    '--no-modify-path',
    '--default-toolchain', $toolchain,
    '--profile', 'minimal'
  )
  Invoke-Checked -FilePath $rustupInit -Arguments $rustupArgs
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
  $cygwinArgs = @(
    '--quiet-mode',
    '--no-admin',
    '--only-site',
    '--root', $Destination,
    '--local-package-dir', $localPkg,
    '--site', $mirror,
    '--packages', $CygwinPackages
  )
  Invoke-Checked -FilePath $setup -Arguments $cygwinArgs
}

function Write-VSCodeSettings {
  <#
  .SYNOPSIS
    VS Code integrated terminal から Cygwin bash を呼び出す settings.json を生成します。

  .PARAMETER VSCodeDir
    VS Code の配置先ディレクトリです。

  .PARAMETER CygwinDir
    Cygwin の配置先ディレクトリです。

  .PARAMETER RustupDir
    rustup ツールチェーンの配置先ディレクトリです。

  .PARAMETER CargoDir
    Cargo の配置先ディレクトリです。

  .PARAMETER PathEntries
    VS Code terminal に渡す PATH エントリです。
  #>
  param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string]$RustupDir,
    [Parameter(Mandatory)][string]$CargoDir,
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
      PATH           = "${envPath};`${env:PATH}"
      TEMP           = $TmpDir
      TMP            = $TmpDir
      PIP_CONFIG_FILE = (Join-Path $ConfigDir 'pip/pip.ini')
      PIP_CACHE_DIR  = (Join-Path $PkgDir 'pip-cache')
      UV_CACHE_DIR   = (Join-Path $PkgDir 'uv-cache')
      npm_config_cache = (Join-Path $PkgDir 'npm-cache')
      npm_config_prefix = $NodeDir
      RUSTUP_HOME    = $RustupDir
      CARGO_HOME     = $CargoDir
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

  .PARAMETER CygwinDir
    Cygwin の配置先ディレクトリです。

  .PARAMETER RustupDir
    rustup ツールチェーンの配置先ディレクトリです。

  .PARAMETER CargoDir
    Cargo の配置先ディレクトリです。

  .PARAMETER PathEntries
    ランチャーに設定する PATH エントリです。
  #>
  param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string]$RustupDir,
    [Parameter(Mandatory)][string]$CargoDir,
    [Parameter(Mandatory)][string[]]$PathEntries
  )
  $vscodeBat = Join-Path $Root 'VSCode.bat'
  $cygwinBat = Join-Path $Root 'Cygwin.bat'
  $launcherRoot = Get-CmdSafePath $Root
  $vscode = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set "PATH=%ROOT%\.local\opt\python;%ROOT%\.local\opt\python\Scripts;%ROOT%\.local\opt\nodejs;%ROOT%\.local\opt\uv;%ROOT%\.local\opt\jq;%ROOT%\.local\opt\pandoc;%ROOT%\.local\opt\cargo\bin;%ROOT%\.local\opt\vscode\bin;%PATH%"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
set "PIP_CONFIG_FILE=%ROOT%\.config\pip\pip.ini"
set "PIP_CACHE_DIR=%ROOT%\.local\pkg\pip-cache"
set "UV_CACHE_DIR=%ROOT%\.local\pkg\uv-cache"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\nodejs"
set "RUSTUP_HOME=%ROOT%\.local\opt\rustup"
set "CARGO_HOME=%ROOT%\.local\opt\cargo"
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
popd
endlocal
exit /b 0
"@
  $cygwin = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set TERM=
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
cd /d "%ROOT%\.local\opt\cygwin\bin" && .\bash --login -i
popd
"@
  Set-Content -LiteralPath $vscodeBat -Value $vscode -Encoding ASCII
  Set-Content -LiteralPath $cygwinBat -Value $cygwin -Encoding ASCII
}

function Test-CommandFile {
  <#
  .SYNOPSIS
    対象ツールのフルパスが存在することを検証し、バージョンを表示します。

  .PARAMETER Name
    ログに表示するツール名です。

  .PARAMETER FilePath
    検証する実行ファイルまたは cmd ファイルのフルパスです。

  .PARAMETER VersionArgs
    バージョン確認に渡す引数です。
  #>
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
  foreach ($d in @($Root,$PkgDir,$OptDir,$ConfigDir,$LogDir,$TmpDir)) { New-Directory $d }
  $env:TEMP = $TmpDir
  $env:TMP = $TmpDir
  Write-Log "Root: $Root" 'STEP'
  Write-Log "Log file: $LogFile" 'INFO'
  Write-Log "TEMP/TMP: $TmpDir" 'INFO'
  if (Test-NetworkPath $Root) {
    Write-Log "Root appears to be on a network path. Keep VPN/authentication online while running installers." 'WARN'
  }

  $PythonDir = Join-Path $OptDir 'python'
  $NodeDir   = Join-Path $OptDir 'nodejs'
  $UvDir     = Join-Path $OptDir 'uv'
  $JqDir     = Join-Path $OptDir 'jq'
  $PandocDir = Join-Path $OptDir 'pandoc'
  $RustupDir = Join-Path $OptDir 'rustup'
  $CargoDir  = Join-Path $OptDir 'cargo'
  $VSCodeDir = Join-Path $OptDir 'vscode'
  $CygwinDir = Join-Path $OptDir 'cygwin'

  foreach ($p in @($PythonDir,$NodeDir,$UvDir,$JqDir,$PandocDir,$RustupDir,$CargoDir,$VSCodeDir,$CygwinDir)) { Assert-UnderDesktop $p }

  Install-PythonEmbedded $PythonDir
  $PythonExe = Join-Path $PythonDir 'python.exe'
  Install-PipFromWheel $PythonExe
  $PipCmd = Join-Path $PythonDir 'Scripts/pip.cmd'
  if (-not (Test-Path -LiteralPath $PipCmd)) {
    throw "pip launcher was not created: $PipCmd"
  }
  Install-NodeZip $NodeDir
  Install-UvZip $UvDir
  Install-JqExe $JqDir
  Install-PandocZip $PandocDir
  Install-Rust $RustupDir $CargoDir
  Install-VSCodeZip $VSCodeDir
  Install-Cygwin $CygwinDir

  $NodeExe = Join-Path $NodeDir 'node.exe'
  $NpmCmd = Join-Path $NodeDir 'npm.cmd'
  $UvExe = Join-Path $UvDir 'uv.exe'
  $JqExe = Join-Path $JqDir 'jq.exe'
  $PandocExe = Join-Path $PandocDir 'pandoc.exe'
  $RustcExe = Join-Path $CargoDir 'bin/rustc.exe'
  $CargoExe = Join-Path $CargoDir 'bin/cargo.exe'
  $CodeCmd = Join-Path $VSCodeDir 'bin/code.cmd'
  $BashExe = Join-Path $CygwinDir 'bin/bash.exe'

  $PathEntries = @(
    $PythonDir,
    (Join-Path $PythonDir 'Scripts'),
    $NodeDir,
    $UvDir,
    $JqDir,
    $PandocDir,
    (Join-Path $CargoDir 'bin'),
    (Join-Path $VSCodeDir 'bin'),
    (Join-Path $CygwinDir 'bin')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  # 日本語コメント: 現プロセス PATH に反映し、この後の検証と VS Code 起動に使う。
  $env:PATH = ($PathEntries -join ';') + ';' + $env:PATH
  $env:TEMP = $TmpDir
  $env:TMP = $TmpDir
  $env:PIP_CONFIG_FILE = Join-Path $ConfigDir 'pip/pip.ini'
  $env:PIP_CACHE_DIR = Join-Path $PkgDir 'pip-cache'
  $env:UV_CACHE_DIR = Join-Path $PkgDir 'uv-cache'
  $env:npm_config_cache = Join-Path $PkgDir 'npm-cache'
  $env:npm_config_prefix = $NodeDir
  $env:RUSTUP_HOME = $RustupDir
  $env:CARGO_HOME  = $CargoDir

  Write-VSCodeSettings -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -RustupDir $RustupDir -CargoDir $CargoDir -PathEntries $PathEntries
  Write-VSCodeExtensionRecommendations -VSCodeDir $VSCodeDir
  Install-VSCodeExtensions -VSCodeDir $VSCodeDir
  Write-Launchers -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -RustupDir $RustupDir -CargoDir $CargoDir -PathEntries $PathEntries

  Write-Log "pip packages installing..." 'STEP'
  Invoke-Checked -FilePath $PipCmd -Arguments @('install', '--no-warn-script-location', 'setuptools', 'wheel')
  Invoke-Checked -FilePath $PipCmd -Arguments @('install', '--no-cache-dir', 'python-docx', 'pypdf', 'Pillow')
  Write-Log "npm packages installing..." 'STEP'
  Invoke-Checked -FilePath $NpmCmd -Arguments @('install', '-g', 'npm', 'cowsay')
  Write-Log "cargo packages installing..." 'STEP'
  Invoke-Checked -FilePath $CargoExe -Arguments @('install', 'ripgrep')

  Test-CommandFile 'python' $PythonExe @('--version')
  Test-CommandFile 'pip' $PipCmd @('--version')
  Test-CommandFile 'node' $NodeExe @('--version')
  Test-CommandFile 'npm' $NpmCmd @('--version')
  Test-CommandFile 'uv' $UvExe @('--version')
  Test-CommandFile 'jq' $JqExe @('--version')
  Test-CommandFile 'pandoc' $PandocExe @('--version')
  Test-CommandFile 'rustc' $RustcExe @('--version')
  Test-CommandFile 'cargo' $CargoExe @('--version')
  Test-CommandFile 'code' $CodeCmd @('--version')
  Test-CommandFile 'cygwin bash' $BashExe @('--version')

  Write-Log "VSCode launcher: $(Join-Path $Root 'VSCode.bat')" 'STEP'
  Write-Log "Cygwin launcher: $(Join-Path $Root 'Cygwin.bat')" 'STEP'
  Write-Log "Installation completed" 'OK'

} catch {
  Write-Log $_.Exception.Message 'ERROR'
  Write-Log "Log file: $LogFile" 'ERROR'
  throw
}
