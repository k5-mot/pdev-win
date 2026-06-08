
[CmdletBinding()]
param(
  [string]$Root = '',

  [string]$PythonVersion = '3.12.10',

  [string]$NodeVersion = '24.16.0',

  [string]$UvVersion = '0.11.18',

  [string]$JqVersion = '1.8.0',

  [string]$PandocVersion = '3.9.0.2',

  [string]$VSCodeVersion = 'stable',

  [string]$CygwinPackages = 'bash,coreutils,curl,git,openssh,vim,nano,make,gcc-core,gcc-g++,tmux',

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
  $Root = [IO.Path]::Combine($DesktopRoot, 'pdev')
}
$Root = [IO.Path]::GetFullPath($Root)
$PkgDir = Join-Path $Root '.local/pkg'
$OptDir = Join-Path $Root '.local/opt'
$BinDir = Join-Path $Root '.local/bin'
$ConfigDir = Join-Path $Root '.config'
$LogDir = Join-Path $Root '.local/logs'
$TmpDir = Join-Path $Root '.local/tmp'
$LogFile = Join-Path $LogDir ('install-{0:yyyyMMdd-HHmmss-fffffff}-{1}.log' -f (Get-Date), $PID)
$CygwinSetupUrl = 'https://cygwin.com/setup-x86_64.exe'
$CygwinMirrors = @(
  'https://ftp.jaist.ac.jp/pub/cygwin/',
  'https://ftp.yamagata-u.ac.jp/pub/cygwin/',
  'https://ftp.iij.ad.jp/pub/cygwin/'
)
$CygwinFallbackMirror = 'https://mirrors.kernel.org/sourceware/cygwin/'
$VSCodeExtensions = @(
#   'ms-vscode-remote.vscode-remote-extensionpack',
#   'ms-vscode-remote.remote-wsl',
#   'ms-vscode-remote.remote-containers',
#   'ms-vscode.remote-server',
#   'ms-vscode-remote.remote-ssh',
#   'ms-vscode-remote.remote-ssh-edit',
#   'ms-vscode.remote-repositories',
#   'ms-vscode.remote-explorer'
  'openai.chatgpt',
#   'anthropic.claude-code',
  'ZooCodeOrganization.zoo-code',
#   'continue.continue',
#   'saoudrizwan.claude-dev',
#   'sst-dev.opencode',
  'zhuangtongfa.Material-theme',
  'pkief.material-icon-theme'
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
    [Parameter(Mandatory)] [string]$Message,
    [ValidateSet('INFO','OK','WARN','ERROR','STEP')] [string]$Level = 'INFO',
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
指定されたパスがネットワークパスかどうかを判定します。
.PARAMETER Path
判定するパスです。
#>
function Test-NetworkPath {
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
複数の候補 URL から最初に取得できたファイルをキャッシュします。
.PARAMETER Candidates
URL とファイル名を持つ候補一覧です。
.PARAMETER ErrorMessage
すべての候補が失敗した場合のエラーメッセージです。
#>
function Download-FirstAvailableCached {
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
バージョン文字列に v 接頭辞を付けたタグ名を返します。
.PARAMETER Version
変換するバージョン文字列です。
#>
function Get-VersionTag {
    param([Parameter(Mandatory)][string]$Version)
  if ($Version.StartsWith('v')) { return $Version }
  return "v$Version"
}

<#
.SYNOPSIS
Python embeddable zip を展開して portable Python を構成します。
.PARAMETER Destination
Python のインストール先ディレクトリです。
.PARAMETER Version
インストールする Python のバージョンです。
#>
function Install-PythonEmbedded {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )
  Write-Log "Installing Python $Version to: $Destination" 'STEP'
  $pyCompact = $Version.Replace('.', '')
  $zip = Download-FirstAvailableCached `
    -Candidates @(
      [pscustomobject]@{
        Url = "https://www.python.org/ftp/python/$Version/python-$Version-embed-amd64.zip"
        FileName = "python-$Version-embed-amd64.zip"
      },
      [pscustomobject]@{
        Url = "https://www.python.org/ftp/python/$Version/python-$Version-embeddable-amd64.zip"
        FileName = "python-$Version-embeddable-amd64.zip"
      }
    ) `
    -ErrorMessage "Could not find the Windows embeddable zip for Python $Version. Specify a version that provides python-$Version-embed-amd64.zip or python-$Version-embeddable-amd64.zip at https://www.python.org/ftp/python/$Version/."
  Expand-ZipClean $zip $Destination
  New-Directory (Join-Path $Destination 'Lib/site-packages')

  $pth = Get-ChildItem -LiteralPath $Destination -Filter 'python*._pth' | Select-Object -First 1
  if ($null -ne $pth) {
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

<#
.SYNOPSIS
PyPI から取得した pip wheel を site-packages へ直接展開します。
.PARAMETER PythonExe
pip を導入する Python 実行ファイルのパスです。
#>
function Install-PipFromWheel {
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

<#
.SYNOPSIS
Node.js の Windows zip を展開します。
.PARAMETER Destination
Node.js のインストール先ディレクトリです。
.PARAMETER Version
インストールする Node.js のバージョンです。
#>
function Install-NodeZip {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )
  Write-Log "Installing Node.js $Version to: $Destination" 'STEP'
  $tag = Get-VersionTag $Version
  $url = "https://nodejs.org/dist/$tag/node-$tag-win-x64.zip"
  $zip = Download-FileCached $url "node-$tag-win-x64.zip"
  Expand-ZipClean $zip $Destination
}

<#
.SYNOPSIS
uv の Windows zip を展開します。
.PARAMETER Destination
uv のインストール先ディレクトリです。
.PARAMETER Version
インストールする uv のバージョンです。
#>
function Install-UvZip {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )
  Write-Log "Installing uv $Version to: $Destination" 'STEP'
  $versionTag = $Version.TrimStart('v')
  $url = "https://releases.astral.sh/github/uv/releases/download/$versionTag/uv-x86_64-pc-windows-msvc.zip"
  $zip = Download-FileCached $url "uv-$versionTag-x86_64-pc-windows-msvc.zip"
  Expand-ZipClean $zip $Destination
}

<#
.SYNOPSIS
jq の Windows 実行ファイルを配置します。
.PARAMETER Destination
jq のインストール先ディレクトリです。
.PARAMETER Version
インストールする jq のバージョンです。
#>
function Install-JqExe {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )
  Write-Log "Installing jq $Version to: $Destination" 'STEP'
  New-Directory $Destination
  $tag = if ($Version.StartsWith('jq-')) { $Version } else { "jq-$Version" }
  $exe = Download-FileCached "https://github.com/jqlang/jq/releases/download/$tag/jq-windows-amd64.exe" "jq-$Version-windows-amd64.exe"
  Copy-Item -LiteralPath $exe -Destination (Join-Path $Destination 'jq.exe') -Force
}

<#
.SYNOPSIS
pandoc の Windows zip を展開します。
.PARAMETER Destination
pandoc のインストール先ディレクトリです。
.PARAMETER Version
インストールする pandoc のバージョンです。
#>
function Install-PandocZip {
    param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Version
  )
  Write-Log "Installing pandoc $Version to: $Destination" 'STEP'
  $url = "https://github.com/jgm/pandoc/releases/download/$Version/pandoc-$Version-windows-x86_64.zip"
  $zip = Download-FileCached $url "pandoc-$Version-windows-x86_64.zip"
  Expand-ZipClean $zip $Destination
}

<#
.SYNOPSIS
GitHub Releases から条件に合う asset を取得します。
.PARAMETER Repo
owner/name 形式の GitHub repository 名です。
.PARAMETER AssetPattern
対象 asset 名を判定する正規表現です。
#>
function Get-GitHubReleaseAsset {
    param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$AssetPattern
  )

  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
  }

  $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers -UseBasicParsing
  foreach ($release in $releases) {
    if ($release.draft -or $release.prerelease) { continue }
    $asset = @($release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1)
    if ($asset.Count -gt 0) {
      return [pscustomobject]@{
        Tag = $release.tag_name
        Name = $asset[0].name
        Url = $asset[0].browser_download_url
      }
    }
  }

  return $null
}

<#
.SYNOPSIS
.local/pkg にある GitHub Releases asset のキャッシュを取得します。
.PARAMETER Name
ツール名です。
.PARAMETER AssetPattern
対象 asset 名を判定する正規表現です。
#>
function Get-CachedGitHubReleaseAsset {
    param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$AssetPattern
  )

  if ($script:InstallForce -or (-not (Test-Path -LiteralPath $PkgDir))) {
    return $null
  }

  $files = @(Get-ChildItem -LiteralPath $PkgDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
  foreach ($file in $files) {
    $assetName = $null
    $tag = $null

    if ($file.Name -match $AssetPattern) {
      $assetName = $file.Name
    } elseif ($file.Name.StartsWith("$Name-", [StringComparison]::OrdinalIgnoreCase)) {
      $suffix = $file.Name.Substring($Name.Length + 1)
      for ($i = 0; $i -lt $suffix.Length; $i++) {
        if ($suffix[$i] -ne '-') { continue }
        if ($i -ge ($suffix.Length - 1)) { continue }

        $candidate = $suffix.Substring($i + 1)
        if ($candidate -match $AssetPattern) {
          $tag = $suffix.Substring(0, $i)
          $assetName = $candidate
          break
        }
      }
    }

    if ($null -ne $assetName) {
      return [pscustomobject]@{
        Tag = $tag
        Name = $assetName
        Path = $file.FullName
      }
    }
  }

  return $null
}

<#
.SYNOPSIS
GitHub Releases の portable asset をダウンロードして配置します。
.PARAMETER Name
ツール名です。
.PARAMETER Repo
owner/name 形式の GitHub repository 名です。
.PARAMETER AssetPattern
対象 asset 名を判定する正規表現です。
.PARAMETER Destination
インストール先ディレクトリです。
.PARAMETER ExeName
配置後の実行ファイル名です。
#>
function Install-GitHubPortableTool {
    param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$AssetPattern,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ExeName
  )

  Write-Log "Installing $Name from GitHub Releases to: $Destination" 'STEP'
  $asset = Get-CachedGitHubReleaseAsset -Name $Name -AssetPattern $AssetPattern
  if ($null -ne $asset) {
    Write-Log "Using cached release asset for ${Name}: $($asset.Name)" 'OK'
    $download = $asset.Path
  } else {
    $asset = Get-GitHubReleaseAsset -Repo $Repo -AssetPattern $AssetPattern
    if ($null -eq $asset) {
      Write-Log "$Name was skipped: no portable Windows x64 release asset matched '$AssetPattern' in $Repo." 'WARN'
      return $false
    }

    Write-Log "$Name release asset: $($asset.Tag) / $($asset.Name)" 'INFO'
    $cacheName = "$Name-$($asset.Tag)-$($asset.Name)"
    $download = Download-FileCached $asset.Url $cacheName
  }

  if ($asset.Name.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
    New-Directory $Destination
    Copy-Item -LiteralPath $download -Destination (Join-Path $Destination $ExeName) -Force
    return $true
  }

  if ($asset.Name.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
    Expand-ZipClean $download $Destination
    return $true
  }

  Write-Log "$Name was skipped: asset '$($asset.Name)' is not a supported portable .zip or .exe." 'WARN'
  return $false
}

<#
.SYNOPSIS
GitHub Releases から portable CLI tools をまとめてインストールします。
.PARAMETER Destinations
ツール名とインストール先ディレクトリの対応表です。
#>
function Install-PortableCliTools {
    param([Parameter(Mandatory)][hashtable]$Destinations)

  $tools = @(
    # @{ Name='genact'; Repo='svenstaro/genact'; Pattern='^genact-[0-9.]+-x86_64-pc-windows-msvc\.exe$'; Exe='genact.exe' },
    @{ Name='bat'; Repo='sharkdp/bat'; Pattern='^bat-v?[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='bat.exe' },
    @{ Name='bottom'; Repo='ClementTsang/bottom'; Pattern='^bottom_x86_64-pc-windows-msvc\.zip$'; Exe='btm.exe' },
    @{ Name='delta'; Repo='dandavison/delta'; Pattern='^delta-[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='delta.exe' },
    @{ Name='dust'; Repo='bootandy/dust'; Pattern='^dust-v?[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='dust.exe' },
    @{ Name='eza'; Repo='eza-community/eza'; Pattern='^eza\.exe_x86_64-pc-windows-gnu\.zip$'; Exe='eza.exe' },
    @{ Name='fd'; Repo='sharkdp/fd'; Pattern='^fd-v?[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='fd.exe' },
    @{ Name='hyperfine'; Repo='sharkdp/hyperfine'; Pattern='^hyperfine-v?[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='hyperfine.exe' },
    @{ Name='procs'; Repo='dalance/procs'; Pattern='^procs-v?[0-9.]+-x86_64-windows\.zip$'; Exe='procs.exe' },
    @{ Name='ripgrep'; Repo='BurntSushi/ripgrep'; Pattern='^ripgrep-[0-9.]+-x86_64-pc-windows-msvc\.zip$'; Exe='rg.exe' }
  )

  foreach ($tool in $tools) {
    Install-GitHubPortableTool `
      -Name $tool.Name `
      -Repo $tool.Repo `
      -AssetPattern $tool.Pattern `
      -Destination $Destinations[$tool.Name] `
      -ExeName $tool.Exe | Out-Null
  }
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
  $localPkg = Join-Path $PkgDir 'cygwin'
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
VSCode portable mode 用の settings.json を生成します。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
.PARAMETER CygwinDir
Cygwin のインストール先ディレクトリです。
.PARAMETER PowerShellPathEntries
PowerShell 用 PATH に追加するディレクトリ一覧です。
.PARAMETER CygwinPathEntries
Cygwin profile 用 PATH に追加するディレクトリ一覧です。
#>
function Write-VSCodeSettings {
    param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string[]]$PowerShellPathEntries,
    [Parameter(Mandatory)][string[]]$CygwinPathEntries
  )
  $settingsPath = Join-Path $VSCodeDir 'data/user-data/User/settings.json'
  $powerShellEnvPath = ($PowerShellPathEntries -join ';').Replace('\','\\')
  $cygwinEnvPath = ($CygwinPathEntries -join ';').Replace('\','\\')
  $settings = [ordered]@{
    'terminal.integrated.defaultProfile.windows' = 'PowerShell-Portable'
    'terminal.integrated.profiles.windows' = [ordered]@{
      'Cygwin' = [ordered]@{
        path = (Join-Path $CygwinDir 'bin/bash.exe')
        args = @('--login','-i')
        icon = 'terminal-bash'
        env = [ordered]@{
          CHERE_INVOKING = '1'
          PATH = $cygwinEnvPath
        }
      }
      'PowerShell-Portable' = [ordered]@{
        path = 'powershell.exe'
        args = @('-NoLogo')
        env = [ordered]@{ PATH = "${powerShellEnvPath};`${env:PATH}" }
      }
    }
    'terminal.integrated.env.windows' = [ordered]@{
      TEMP           = $TmpDir
      TMP            = $TmpDir
      PIP_CONFIG_FILE = (Join-Path $ConfigDir 'pip/pip.ini')
      PIP_CACHE_DIR  = (Join-Path $PkgDir 'pip-cache')
      UV_CACHE_DIR   = (Join-Path $PkgDir 'uv-cache')
      npm_config_cache = (Join-Path $PkgDir 'npm-cache')
      npm_config_prefix = $NodeDir
    }
    'workbench.colorTheme' = 'Visual Studio Dark'
    'window.commandCenter' = $false
    'chat.titleBar.signIn.enabled' = $false
    'chat.disableAIFeatures' = $true
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
  $extensions = [ordered]@{
    recommendations = $VSCodeExtensions
  }
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
.local/bin に配置する cmd shim を生成します。
.PARAMETER Name
生成する shim のファイル名です。
.PARAMETER TargetRelativePath
Root から見た実体コマンドの相対パスです。
#>
function Write-CmdShim {
    param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$TargetRelativePath
  )

  New-Directory $BinDir
  $shimPath = Join-Path $BinDir $Name
  $target = $TargetRelativePath -replace '/', '\'
  $body = @"
@echo off
setlocal
set "ROOT=%~dp0..\.."
"%ROOT%\$target" %*
exit /b %ERRORLEVEL%
"@
  Set-Content -LiteralPath $shimPath -Value $body -Encoding ASCII
}

<#
.SYNOPSIS
portable tools 用の cmd shim を .local/bin にまとめて生成します。
#>
function Write-PortableBinShims {
  $shims = @(
    @{ Name='uv.cmd'; Target='.local/opt/uv/uv.exe' },
    @{ Name='jq.cmd'; Target='.local/opt/jq/jq.exe' },
    @{ Name='pandoc.cmd'; Target='.local/opt/pandoc/pandoc.exe' },
    @{ Name='bat.cmd'; Target='.local/opt/bat/bat.exe' },
    @{ Name='btm.cmd'; Target='.local/opt/bottom/btm.exe' },
    @{ Name='delta.cmd'; Target='.local/opt/delta/delta.exe' },
    @{ Name='dust.cmd'; Target='.local/opt/dust/dust.exe' },
    @{ Name='eza.cmd'; Target='.local/opt/eza/eza.exe' },
    @{ Name='fd.cmd'; Target='.local/opt/fd/fd.exe' },
    @{ Name='genact.cmd'; Target='.local/opt/genact/genact.exe' },
    @{ Name='hyperfine.cmd'; Target='.local/opt/hyperfine/hyperfine.exe' },
    @{ Name='procs.cmd'; Target='.local/opt/procs/procs.exe' },
    @{ Name='rg.cmd'; Target='.local/opt/ripgrep/rg.exe' }
  )

  foreach ($shim in $shims) {
    Write-CmdShim -Name $shim.Name -TargetRelativePath $shim.Target
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
Root 直下に VSCode、Cygwin、PowerShell の launcher を生成します。
.PARAMETER VSCodeDir
VSCode のインストール先ディレクトリです。
.PARAMETER CygwinDir
Cygwin のインストール先ディレクトリです。
.PARAMETER PowerShellPathEntries
PowerShell launcher 用 PATH に追加するディレクトリ一覧です。
.PARAMETER CygwinPathEntries
Cygwin launcher 用 PATH に追加するディレクトリ一覧です。
#>
function Write-Launchers {
    param(
    [Parameter(Mandatory)][string]$VSCodeDir,
    [Parameter(Mandatory)][string]$CygwinDir,
    [Parameter(Mandatory)][string[]]$PowerShellPathEntries,
    [Parameter(Mandatory)][string[]]$CygwinPathEntries
  )
  $vscodeCmd = Join-Path $Root 'VSCode.cmd'
  $cygwinCmd = Join-Path $Root 'Cygwin.cmd'
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
set "PIP_CONFIG_FILE=%ROOT%\.config\pip\pip.ini"
set "PIP_CACHE_DIR=%ROOT%\.local\pkg\pip-cache"
set "UV_CACHE_DIR=%ROOT%\.local\pkg\uv-cache"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\nodejs"
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
set "PATH=%ROOT%\.local\opt\cygwin\bin"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
cd /d "%ROOT%\.local\opt\cygwin\bin" && .\bash --login -i
popd
"@
  $powerShell = @"
@echo off
setlocal enableextensions
pushd "$launcherRoot" || exit /b 1
set "ROOT=%CD%"
set "PATH=$launcherPath;%PATH%"
set "TEMP=%ROOT%\.local\tmp"
set "TMP=%ROOT%\.local\tmp"
set "PIP_CONFIG_FILE=%ROOT%\.config\pip\pip.ini"
set "PIP_CACHE_DIR=%ROOT%\.local\pkg\pip-cache"
set "UV_CACHE_DIR=%ROOT%\.local\pkg\uv-cache"
set "npm_config_cache=%ROOT%\.local\pkg\npm-cache"
set "npm_config_prefix=%ROOT%\.local\opt\nodejs"
set "CODEX_HOME=%ROOT%\.config\codex"
set "CODEX_SQLITE_HOME=%ROOT%\.cache\codex"
set "LITELLM_API_KEY=sk-litellm-master-key"
powershell.exe -NoLogo
popd
endlocal
"@
  Set-Content -LiteralPath $vscodeCmd -Value $vscode -Encoding ASCII
  Set-Content -LiteralPath $cygwinCmd -Value $cygwin -Encoding ASCII
  Set-Content -LiteralPath $powerShellCmd -Value $powerShell -Encoding ASCII
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
  foreach ($d in @($Root,$PkgDir,$OptDir,$BinDir,$ConfigDir,$LogDir,$TmpDir)) { New-Directory $d }
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
  $VSCodeDir = Join-Path $OptDir 'vscode'
  $CygwinDir = Join-Path $OptDir 'cygwin'
  $PortableToolDirs = @{
    bat = Join-Path $OptDir 'bat'
    bottom = Join-Path $OptDir 'bottom'
    delta = Join-Path $OptDir 'delta'
    dust = Join-Path $OptDir 'dust'
    eza = Join-Path $OptDir 'eza'
    fd = Join-Path $OptDir 'fd'
    genact = Join-Path $OptDir 'genact'
    hyperfine = Join-Path $OptDir 'hyperfine'
    procs = Join-Path $OptDir 'procs'
    ripgrep = Join-Path $OptDir 'ripgrep'
  }

  foreach ($p in @($PythonDir,$NodeDir,$UvDir,$JqDir,$PandocDir,$VSCodeDir,$CygwinDir,$BinDir) + $PortableToolDirs.Values) { Assert-UnderDesktop $p }

  Install-PythonEmbedded -Destination $PythonDir -Version $PythonVersion
  $PythonExe = Join-Path $PythonDir 'python.exe'
  Install-PipFromWheel $PythonExe
  $PipCmd = Join-Path $PythonDir 'Scripts/pip.cmd'
  if (-not (Test-Path -LiteralPath $PipCmd)) {
    throw "pip launcher was not created: $PipCmd"
  }
  Install-NodeZip -Destination $NodeDir -Version $NodeVersion
  $NpmCmd = Join-Path $NodeDir 'npm.cmd'
  if (-not (Test-Path -LiteralPath $NpmCmd)) {
    throw "npm launcher was not created: $NpmCmd"
  }
  Install-UvZip -Destination $UvDir -Version $UvVersion
  Install-JqExe -Destination $JqDir -Version $JqVersion
  Install-PandocZip -Destination $PandocDir -Version $PandocVersion
  Install-PortableCliTools -Destinations $PortableToolDirs
  Install-VSCodeZip -Destination $VSCodeDir -Version $VSCodeVersion
  Install-Cygwin -Destination $CygwinDir -Packages $CygwinPackages
  Write-PortableBinShims

  $NodeExe = Join-Path $NodeDir 'node.exe'
  $UvCmd = Join-Path $BinDir 'uv.cmd'
  $JqCmd = Join-Path $BinDir 'jq.cmd'
  $PandocCmd = Join-Path $BinDir 'pandoc.cmd'
  $BatCmd = Join-Path $BinDir 'bat.cmd'
  $BottomCmd = Join-Path $BinDir 'btm.cmd'
  $DeltaCmd = Join-Path $BinDir 'delta.cmd'
  $DustCmd = Join-Path $BinDir 'dust.cmd'
  $EzaCmd = Join-Path $BinDir 'eza.cmd'
  $FdCmd = Join-Path $BinDir 'fd.cmd'
  $GenactCmd = Join-Path $BinDir 'genact.cmd'
  $HyperfineCmd = Join-Path $BinDir 'hyperfine.cmd'
  $ProcsCmd = Join-Path $BinDir 'procs.cmd'
  $RipgrepCmd = Join-Path $BinDir 'rg.cmd'
  $CodeCmd = Join-Path $VSCodeDir 'bin/code.cmd'
  $BashExe = Join-Path $CygwinDir 'bin/bash.exe'

  $PowerShellPathEntries = @(
    $BinDir,
    $PythonDir,
    (Join-Path $PythonDir 'Scripts'),
    $NodeDir,
    (Join-Path $VSCodeDir 'bin'),
    (Join-Path $CygwinDir 'bin')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  $CygwinPathEntries = @(
    (Join-Path $CygwinDir 'bin')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  $env:PATH = ($PowerShellPathEntries -join ';') + ';' + $env:PATH
  $env:TEMP = $TmpDir
  $env:TMP = $TmpDir
  $env:PIP_CONFIG_FILE = Join-Path $ConfigDir 'pip/pip.ini'
  $env:PIP_CACHE_DIR = Join-Path $PkgDir 'pip-cache'
  $env:UV_CACHE_DIR = Join-Path $PkgDir 'uv-cache'
  $env:npm_config_cache = Join-Path $PkgDir 'npm-cache'
  $env:npm_config_prefix = $NodeDir

  Write-VSCodeSettings -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -PowerShellPathEntries $PowerShellPathEntries -CygwinPathEntries $CygwinPathEntries
  Write-VSCodeExtensionRecommendations -VSCodeDir $VSCodeDir
  Install-VSCodeExtensions -VSCodeDir $VSCodeDir
  Write-Launchers -VSCodeDir $VSCodeDir -CygwinDir $CygwinDir -PowerShellPathEntries $PowerShellPathEntries -CygwinPathEntries $CygwinPathEntries

  Write-Log "pip packages installing..." 'STEP' -LogOnly
  Invoke-Checked -FilePath $PipCmd -Arguments @('install', '--no-warn-script-location', 'setuptools', 'wheel') -LogOnly
  Invoke-Checked -FilePath $PipCmd -Arguments @('install', '--no-cache-dir', 'python-docx', 'pypdf', 'Pillow') -LogOnly
  Write-Log "npm packages installing..." 'STEP' -LogOnly
  Invoke-Checked -FilePath $NpmCmd -Arguments @('install', '-g', 'npm', 'cowsay') -LogOnly

  Test-CommandFile 'python' $PythonExe @('--version')
  Test-CommandFile 'pip' $PipCmd @('--version')
  Test-CommandFile 'node' $NodeExe @('--version')
  Test-CommandFile 'npm' $NpmCmd @('--version')
  Test-CommandFile 'uv' $UvCmd @('--version')
  Test-CommandFile 'jq' $JqCmd @('--version')
  Test-CommandFile 'pandoc' $PandocCmd @('--version')
  Test-CommandFile 'bat' $BatCmd @('--version')
  Test-CommandFile 'bottom' $BottomCmd @('--version')
  Test-CommandFile 'delta' $DeltaCmd @('--version')
  Test-CommandFile 'dust' $DustCmd @('--version')
  Test-CommandFile 'eza' $EzaCmd @('--version')
  Test-CommandFile 'fd' $FdCmd @('--version')
  Test-CommandFile 'hyperfine' $HyperfineCmd @('--version')
  Test-CommandFile 'procs' $ProcsCmd @('--version')
  Test-CommandFile 'ripgrep' $RipgrepCmd @('--version')
  Test-CommandFile 'code' $CodeCmd @('--version')
  Test-CommandFile 'cygwin bash' $BashExe @('--version')

  Write-Log "VSCode launcher: $(Join-Path $Root 'VSCode.cmd')" 'STEP'
  Write-Log "Cygwin launcher: $(Join-Path $Root 'Cygwin.cmd')" 'STEP'
  Write-Log "PowerShell launcher: $(Join-Path $Root 'PowerShell.cmd')" 'STEP'
  Write-Log "Installation completed" 'OK'

} catch {
  Write-Log $_.Exception.Message 'ERROR'
  Write-Log "Log file: $LogFile" 'ERROR'
  throw
}
