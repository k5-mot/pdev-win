
[CmdletBinding()]
param(
  [string]$Root = '',

  [string]$MiseVersion = 'latest',

  [string]$PythonVersion = '3.12.10',

  [string]$NodeVersion = '24.16.0',

  [string]$UvVersion = '0.11.18',

  [string]$JqVersion = '1.8.0',

  [string]$PandocVersion = '3.9.0.2',

  [string]$VSCodeVersion = 'stable',

  [string]$GitHubToken = '',

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
  $Root = [IO.Path]::Combine($DesktopRoot, 'pdev-mise')
}
$Root = [IO.Path]::GetFullPath($Root)
$PkgDir = Join-Path $Root '.local/pkg'
$OptDir = Join-Path $Root '.local/opt'
$BinDir = Join-Path $Root '.local/bin'
$ConfigDir = Join-Path $Root '.config'
$LogDir = Join-Path $Root '.local/logs'
$TmpDir = Join-Path $Root '.local/tmp'
$LogFile = Join-Path $LogDir ('install-v8-{0:yyyyMMdd-HHmmss-fffffff}-{1}.log' -f (Get-Date), $PID)

$MiseDir = Join-Path $OptDir 'mise'
$MiseExe = Join-Path $MiseDir 'mise.exe'
$MiseToml = Join-Path $Root 'mise.toml'
$MiseDataDir = Join-Path $Root '.local/share/mise'
$MiseCacheDir = Join-Path $Root '.local/pkg/mise-cache'
$MiseStateDir = Join-Path $Root '.local/state/mise'
$MiseConfigDir = Join-Path $Root '.config/mise'
$MiseShimsDir = Join-Path $MiseDataDir 'shims'
$NpmGlobalDir = Join-Path $Root '.local/opt/npm-global'

$VSCodeExtensions = @(
  'openai.chatgpt',
  'ZooCodeOrganization.zoo-code',
  'zhuangtongfa.Material-theme',
  'pkief.material-icon-theme'
)

$MiseTools = @(
  [ordered]@{ Id='python'; Version=$PythonVersion; Commands=@(@{ Name='python'; Args=@('--version') }, @{ Name='pip'; Args=@('--version') }) },
  [ordered]@{ Id='node'; Version=$NodeVersion; Commands=@(@{ Name='node'; Args=@('--version') }, @{ Name='npm'; Args=@('--version') }) },
  [ordered]@{ Id='uv'; Version=$UvVersion; Commands=@(@{ Name='uv'; Args=@('--version') }) },
  [ordered]@{ Id='jq'; Version=$JqVersion; Commands=@(@{ Name='jq'; Args=@('--version') }) },
  [ordered]@{ Id='pandoc'; Version=$PandocVersion; Commands=@(@{ Name='pandoc'; Args=@('--version') }) },
  [ordered]@{ Id='github:sharkdp/bat'; Version='latest'; Commands=@(@{ Name='bat'; Args=@('--version') }) },
  [ordered]@{ Id='github:ClementTsang/bottom'; Version='latest'; Commands=@(@{ Name='btm'; Args=@('--version') }) },
  [ordered]@{ Id='github:google/go-containerregistry'; Version='latest'; Commands=@(@{ Name='crane'; Args=@('version') }) },
  [ordered]@{ Id='github:dandavison/delta'; Version='latest'; Commands=@(@{ Name='delta'; Args=@('--version') }) },
  [ordered]@{ Id='github:bootandy/dust'; Version='latest'; Commands=@(@{ Name='dust'; Args=@('--version') }) },
  [ordered]@{ Id='github:eza-community/eza'; Version='latest'; Commands=@(@{ Name='eza'; Args=@('--version') }) },
  [ordered]@{ Id='github:sharkdp/fd'; Version='latest'; Commands=@(@{ Name='fd'; Args=@('--version') }) },
  [ordered]@{ Id='github:sharkdp/hyperfine'; Version='latest'; Commands=@(@{ Name='hyperfine'; Args=@('--version') }) },
  [ordered]@{ Id='github:dalance/procs'; Version='latest'; Commands=@(@{ Name='procs'; Args=@('--version') }) },
  [ordered]@{ Id='github:BurntSushi/ripgrep'; Version='latest'; Commands=@(@{ Name='rg'; Args=@('--version') }) }
)

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
    INFO  = @{ Color='Cyan' }
    OK    = @{ Color='Green' }
    WARN  = @{ Color='Yellow' }
    ERROR = @{ Color='Red' }
    STEP  = @{ Color='Magenta' }
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
zip ファイルを展開先へクリーン展開します。
.PARAMETER ZipPath
展開する zip ファイルのパスです。
.PARAMETER Destination
展開先ディレクトリです。
#>
function Expand-ZipClean {
    param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$Destination
  )

  $tmp = Join-Path $TmpDir ('pdev-v8-' + [guid]::NewGuid().ToString('N'))
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
mise に渡す環境変数を現在の PowerShell プロセスへ設定します。
#>
function Set-MiseEnvironment {
  $env:MISE_DATA_DIR = $MiseDataDir
  $env:MISE_CACHE_DIR = $MiseCacheDir
  $env:MISE_STATE_DIR = $MiseStateDir
  $env:MISE_CONFIG_DIR = $MiseConfigDir
  $env:MISE_GLOBAL_CONFIG_FILE = Join-Path $MiseConfigDir 'config.toml'
  $env:MISE_TRUSTED_CONFIG_PATHS = $Root
  $env:MISE_YES = '1'
  $env:MISE_JOBS = '4'
  $env:TEMP = $TmpDir
  $env:TMP = $TmpDir
  $env:npm_config_cache = Join-Path $PkgDir 'npm-cache'
  $env:npm_config_prefix = $NpmGlobalDir
  $env:PATH = (@($BinDir,$MiseDir,$NpmGlobalDir) -join ';') + ';' + $env:PATH
}

<#
.SYNOPSIS
GitHub Releases を多用する mise 用の認証情報を現在のプロセスへ設定します。
#>
function Initialize-GitHubAuth {
  if (-not [string]::IsNullOrWhiteSpace($GitHubToken)) {
    $env:GITHUB_TOKEN = $GitHubToken
    Write-Log 'Using GitHub token from -GitHubToken.' 'INFO'
    return
  }
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    Write-Log 'Using GitHub token from GITHUB_TOKEN.' 'INFO'
    return
  }

  $gh = Get-Command 'gh' -ErrorAction SilentlyContinue
  if ($null -eq $gh) {
    Write-Log 'GITHUB_TOKEN is not set. GitHub-backed mise tools may hit the unauthenticated rate limit.' 'WARN'
    return
  }

  try {
    $token = (& $gh.Source auth token 2>$null | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $env:GITHUB_TOKEN = $token.Trim()
      Write-Log 'Using GitHub token from gh auth token.' 'INFO'
      return
    }
  } catch {
  }
  Write-Log 'Could not get a GitHub token from gh. GitHub-backed mise tools may hit the unauthenticated rate limit.' 'WARN'
}

<#
.SYNOPSIS
GitHub API の残量を確認し、mise 実行前にレート制限の問題を検出します。
#>
function Test-GitHubApiBudget {
  $githubToolCount = @($MiseTools | Where-Object { $_.Id -like 'github:*' -or $_.Id -eq 'pandoc' }).Count
  if ($githubToolCount -eq 0) {
    return
  }

  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
  }

  try {
    $rate = Invoke-RestMethod -Uri 'https://api.github.com/rate_limit' -Headers $headers -UseBasicParsing
    $remaining = [int]$rate.resources.core.remaining
    $limit = [int]$rate.resources.core.limit
    $resetLocal = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rate.resources.core.reset).LocalDateTime
    Write-Log "GitHub API rate limit: $remaining/$limit, reset: $resetLocal" 'INFO'
    if ($remaining -lt ($githubToolCount * 3)) {
      throw "GitHub API rate limit is too low for mise GitHub tools. Set GITHUB_TOKEN or pass -GitHubToken, then rerun. Reset: $resetLocal"
    }
  } catch {
    if ($_.Exception.Message -like 'GitHub API rate limit is too low*') {
      throw
    }
    Write-Log "Could not check GitHub API rate limit: $($_.Exception.Message)" 'WARN'
  }
}

<#
.SYNOPSIS
GitHub Releases から mise.exe を取得して配置します。
#>
function Install-Mise {
  New-Directory $MiseDir
  if ((Test-Path -LiteralPath $MiseExe) -and (-not $script:InstallForce)) {
    Write-Log "Using existing mise: $MiseExe" 'OK'
    return
  }

  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
  }
  $releaseUri = if ($MiseVersion -in @('latest','stable')) {
    'https://api.github.com/repos/jdx/mise/releases/latest'
  } else {
    "https://api.github.com/repos/jdx/mise/releases/tags/$MiseVersion"
  }
  $release = Invoke-RestMethod -Uri $releaseUri -Headers $headers -UseBasicParsing
  $asset = @($release.assets | Where-Object { $_.name -match '^mise-.*-windows-x64\.exe$' } | Select-Object -First 1)
  if ($asset.Count -eq 0) {
    throw "Could not find mise windows-x64 exe asset in release: $($release.tag_name)"
  }

  $download = Download-FileCached -Url $asset[0].browser_download_url -FileName $asset[0].name
  Copy-Item -LiteralPath $download -Destination $MiseExe -Force
}

<#
.SYNOPSIS
Root 配下の mise.toml を生成します。
#>
function Write-MiseToml {
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('[tools]') | Out-Null
  foreach ($tool in $MiseTools) {
    $lines.Add(('"{0}" = "{1}"' -f $tool.Id, $tool.Version)) | Out-Null
  }
  $lines.Add('') | Out-Null
  $lines.Add('[settings]') | Out-Null
  $lines.Add('experimental = true') | Out-Null
  Set-Content -LiteralPath $MiseToml -Value $lines.ToArray() -Encoding UTF8
}

<#
.SYNOPSIS
mise.toml に記載した tools をインストールします。
#>
function Install-MiseTools {
  Invoke-Checked -FilePath $MiseExe -Arguments @('trust', '-y', $MiseToml) -LogOnly
  Invoke-Checked -FilePath $MiseExe -Arguments @('install', '-v', '-y', '-C', $Root) -LogOnly
}

<#
.SYNOPSIS
mise が管理する Python と Node.js に追加パッケージを入れます。
#>
function Install-LanguagePackages {
  Write-Log "pip packages installing via mise..." 'STEP' -LogOnly
  Invoke-Checked -FilePath $MiseExe -Arguments @('exec', '-C', $Root, '--', 'python', '-m', 'pip', 'install', '--no-warn-script-location', 'setuptools', 'wheel') -LogOnly
  Invoke-Checked -FilePath $MiseExe -Arguments @('exec', '-C', $Root, '--', 'python', '-m', 'pip', 'install', '--no-cache-dir', 'python-docx', 'pypdf', 'Pillow') -LogOnly

  Write-Log "npm packages installing via mise..." 'STEP' -LogOnly
  New-Directory $NpmGlobalDir
  Invoke-Checked -FilePath $MiseExe -Arguments @('exec', '-C', $Root, '--', 'npm', 'install', '-g', 'npm', 'cowsay') -LogOnly
}

<#
.SYNOPSIS
VSCode の portable archive を展開して data ディレクトリを作成します。
.PARAMETER Destination
VSCode のインストール先ディレクトリです。
.PARAMETER Version
インストールする VSCode のバージョンです。
#>
function Install-VSCodeZip {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )

  Write-Log "Installing VSCode $Version to: $Destination" 'STEP'
  $versionSegment = if ($Version -in @('stable','latest')) { 'latest' } else { $Version }
  $url = "https://update.code.visualstudio.com/$versionSegment/win32-x64-archive/stable"
  $zip = Download-FileCached $url "vscode-$versionSegment-win32-x64-archive.zip"
  Expand-ZipClean $zip $Destination
  New-Directory (Join-Path $Destination 'data')
  New-Directory (Join-Path $Destination 'data/user-data/User')
  New-Directory (Join-Path $Destination 'data/extensions')
}

<#
.SYNOPSIS
VSCode portable mode 用の settings.json を生成します。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
.PARAMETER PowerShellPathEntries
PowerShell 用 PATH に追加するディレクトリ一覧です。
#>
function Write-VSCodeSettings {
    param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string[]]$PowerShellPathEntries
  )

  $settingsPath = Join-Path $VSCodeDir 'data/user-data/User/settings.json'
  $powerShellEnvPath = ($PowerShellPathEntries -join ';').Replace('\','\\')
  $settings = [ordered]@{
    'terminal.integrated.defaultProfile.windows' = 'PowerShell-Portable'
    'terminal.integrated.profiles.windows' = [ordered]@{
      'PowerShell-Portable' = [ordered]@{
        path = 'powershell.exe'
        args = @('-NoLogo')
        env = [ordered]@{
          PATH = "${powerShellEnvPath};`${env:PATH}"
          MISE_DATA_DIR = $MiseDataDir
          MISE_CACHE_DIR = $MiseCacheDir
          MISE_STATE_DIR = $MiseStateDir
          MISE_CONFIG_DIR = $MiseConfigDir
          MISE_GLOBAL_CONFIG_FILE = (Join-Path $MiseConfigDir 'config.toml')
          MISE_TRUSTED_CONFIG_PATHS = $Root
        }
      }
    }
    'terminal.integrated.env.windows' = [ordered]@{
      TEMP = $TmpDir
      TMP = $TmpDir
      MISE_DATA_DIR = $MiseDataDir
      MISE_CACHE_DIR = $MiseCacheDir
      MISE_STATE_DIR = $MiseStateDir
      MISE_CONFIG_DIR = $MiseConfigDir
      MISE_GLOBAL_CONFIG_FILE = (Join-Path $MiseConfigDir 'config.toml')
      MISE_TRUSTED_CONFIG_PATHS = $Root
      npm_config_cache = (Join-Path $PkgDir 'npm-cache')
      npm_config_prefix = $NpmGlobalDir
    }
    'workbench.colorTheme' = 'Visual Studio Dark'
    'window.commandCenter' = $false
    'chat.disableAIFeatures' = $true
    'chat.titleBar.signIn.enabled' = $false
    'chat.titleBar.openInAgentsWindow.enabled' = $false
  }
  $json = $settings | ConvertTo-Json -Depth 20
  Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
}

<#
.SYNOPSIS
VSCode の推奨拡張機能ファイルを生成します。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
#>
function Write-VSCodeExtensionRecommendations {
    param([Parameter(Mandatory)][string]$VSCodeDir)

  $extensionsPath = Join-Path $VSCodeDir 'data/user-data/User/extensions.json'
  $extensions = [ordered]@{ recommendations = $VSCodeExtensions }
  $json = $extensions | ConvertTo-Json -Depth 10
  Set-Content -LiteralPath $extensionsPath -Value $json -Encoding UTF8
}

<#
.SYNOPSIS
VSCode CLI を使って拡張機能を portable extensions dir にインストールします。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
#>
function Install-VSCodeExtensions {
    param([Parameter(Mandatory)][string]$VSCodeDir)

  $codeCmd = Join-Path $VSCodeDir 'bin/code.cmd'
  $userDataDir = Join-Path $VSCodeDir 'data/user-data'
  $extensionsDir = Join-Path $VSCodeDir 'data/extensions'
  foreach ($extensionId in $VSCodeExtensions) {
    Write-Log "Installing VSCode extension: $extensionId" 'STEP' -LogOnly
    Invoke-Checked -FilePath $codeCmd -Arguments @(
      '--user-data-dir', $userDataDir,
      '--extensions-dir', $extensionsDir,
      '--install-extension', $extensionId,
      '--force'
    ) -LogOnly
  }
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
Root 直下に VSCode と PowerShell の launcher を生成します。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
.PARAMETER PowerShellPathEntries
PowerShell launcher 用 PATH に追加するディレクトリ一覧です。
#>
function Write-Launchers {
    param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string[]]$PowerShellPathEntries
  )

  $vscodeCmd = Join-Path $Root 'VSCode.cmd'
  $powerShellCmd = Join-Path $Root 'PowerShell.cmd'
  $launcherRoot = Get-CmdSafePath $Root
  $launcherPath = ($PowerShellPathEntries | ForEach-Object { '%ROOT%' + $_.Substring($Root.Length) }) -join ';'
  $vscode = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set "PATH=$launcherPath;%PATH%"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
set "MISE_DATA_DIR=%ROOT%\.local\share\mise"
set "MISE_CACHE_DIR=%ROOT%\.local\pkg\mise-cache"
set "MISE_STATE_DIR=%ROOT%\.local\state\mise"
set "MISE_CONFIG_DIR=%ROOT%\.config\mise"
set "MISE_GLOBAL_CONFIG_FILE=%ROOT%\.config\mise\config.toml"
set "MISE_TRUSTED_CONFIG_PATHS=%ROOT%"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\npm-global"
set "CODE=%ROOT%\.local\opt\vscode\Code.exe"
set "VSCODE_USER_DATA=%ROOT%\.local\opt\vscode\data\user-data"
set "VSCODE_EXTENSIONS=%ROOT%\.local\opt\vscode\data\extensions"
set "CODEX_HOME=%ROOT%\.config\codex"
set "CODEX_SQLITE_HOME=%ROOT%\.cache\codex"

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
  $powerShell = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set "PATH=$launcherPath;%PATH%"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
set "MISE_DATA_DIR=%ROOT%\.local\share\mise"
set "MISE_CACHE_DIR=%ROOT%\.local\pkg\mise-cache"
set "MISE_STATE_DIR=%ROOT%\.local\state\mise"
set "MISE_CONFIG_DIR=%ROOT%\.config\mise"
set "MISE_GLOBAL_CONFIG_FILE=%ROOT%\.config\mise\config.toml"
set "MISE_TRUSTED_CONFIG_PATHS=%ROOT%"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\npm-global"
set "CODEX_HOME=%ROOT%\.config\codex"
set "CODEX_SQLITE_HOME=%ROOT%\.cache\codex"
powershell.exe -NoLogo
popd
endlocal
"@
  Set-Content -LiteralPath $vscodeCmd -Value $vscode -Encoding ASCII
  Set-Content -LiteralPath $powerShellCmd -Value $powerShell -Encoding ASCII
}

<#
.SYNOPSIS
Windows の mise shim を直接使わず、mise exec 経由で起動する cmd ラッパーを生成します。
#>
function Write-MiseCommandWrappers {
  $commandNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($tool in $MiseTools) {
    foreach ($command in $tool.Commands) {
      [void]$commandNames.Add([string]$command.Name)
    }
  }
  foreach ($extra in @('corepack','npx')) {
    [void]$commandNames.Add($extra)
  }

  foreach ($commandName in ($commandNames | Sort-Object)) {
    $wrapperPath = Join-Path $BinDir ($commandName + '.cmd')
    $wrapper = @"
@echo off
setlocal enableextensions
set "ROOT=$Root"
set "MISE_DATA_DIR=%ROOT%\.local\share\mise"
set "MISE_CACHE_DIR=%ROOT%\.local\pkg\mise-cache"
set "MISE_STATE_DIR=%ROOT%\.local\state\mise"
set "MISE_CONFIG_DIR=%ROOT%\.config\mise"
set "MISE_GLOBAL_CONFIG_FILE=%ROOT%\.config\mise\config.toml"
set "MISE_TRUSTED_CONFIG_PATHS=%ROOT%"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\npm-global"
"%ROOT%\.local\opt\mise\mise.exe" exec -C "%ROOT%" -- $commandName %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $wrapperPath -Value $wrapper -Encoding ASCII
  }
}

<#
.SYNOPSIS
指定されたコマンドのバージョン出力を確認します。
.PARAMETER Name
ログに表示するツール名です。
.PARAMETER Command
実行するコマンドです。
.PARAMETER VersionArgs
バージョン確認に使う引数です。
#>
function Test-MiseCommand {
    param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Command,
    [string[]]$VersionArgs = @('--version')
  )

  $source = if (Test-Path -LiteralPath $Command) {
    [IO.Path]::GetFullPath($Command)
  } else {
    (Get-Command $Command -ErrorAction Stop).Source
  }
  Write-Log "$Name path OK: $source" 'OK'
  $ver = & $source @VersionArgs 2>&1 | Select-Object -First 3
  Write-Log ("$Name version: " + (($ver -join ' ') -replace '\s+', ' ')) 'OK'
}

try {
  Assert-UnderDesktop $Root
  foreach ($d in @($Root,$PkgDir,$OptDir,$BinDir,$ConfigDir,$LogDir,$TmpDir,$MiseDataDir,$MiseCacheDir,$MiseStateDir,$MiseConfigDir,$NpmGlobalDir)) {
    New-Directory $d
    Assert-UnderDesktop $d
  }

  Write-Log "Root: $Root" 'STEP'
  Write-Log "Log file: $LogFile" 'INFO'
  Write-Log "TEMP/TMP: $TmpDir" 'INFO'

  Set-MiseEnvironment
  Initialize-GitHubAuth
  Test-GitHubApiBudget
  Install-Mise
  Write-MiseToml
  Install-MiseTools
  Install-LanguagePackages
  Write-MiseCommandWrappers

  $VSCodeDir = Join-Path $OptDir 'vscode'
  Assert-UnderDesktop $VSCodeDir
  Install-VSCodeZip -Destination $VSCodeDir -Version $VSCodeVersion

  $PowerShellPathEntries = @(
    $BinDir,
    $MiseDir,
    $NpmGlobalDir,
    (Join-Path $VSCodeDir 'bin')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  $env:PATH = ($PowerShellPathEntries -join ';') + ';' + $env:PATH
  Write-VSCodeSettings -VSCodeDir $VSCodeDir -PowerShellPathEntries $PowerShellPathEntries
  Write-VSCodeExtensionRecommendations -VSCodeDir $VSCodeDir
  Install-VSCodeExtensions -VSCodeDir $VSCodeDir
  Write-Launchers -VSCodeDir $VSCodeDir -PowerShellPathEntries $PowerShellPathEntries

  Test-MiseCommand 'mise' 'mise' @('--version')
  foreach ($tool in $MiseTools) {
    foreach ($command in $tool.Commands) {
      Test-MiseCommand $command.Name $command.Name @($command.Args)
    }
  }
  Test-MiseCommand 'code' (Join-Path $VSCodeDir 'bin/code.cmd') @('--version')

  Write-Log "VSCode launcher: $(Join-Path $Root 'VSCode.cmd')" 'STEP'
  Write-Log "PowerShell launcher: $(Join-Path $Root 'PowerShell.cmd')" 'STEP'
  Write-Log "mise config: $MiseToml" 'STEP'
  Write-Log "Installation completed" 'OK'
} catch {
  Write-Log $_.Exception.Message 'ERROR'
  Write-Log "Log file: $LogFile" 'ERROR'
  throw
}
