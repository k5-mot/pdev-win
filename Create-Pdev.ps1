param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot,

    [string]$PythonVersion = '3.12.10',
    [string]$NodejsVersion = '22.16.0',
    [string]$UvVersion = '0.7.8',
    [string]$JqVersion = '1.7.1',
    [string]$PandocVersion = '3.7.0.2',
    [string]$VscodeVersion = '1.100.2',
    [string]$StartBatPath,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $unresolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    return [System.IO.Path]::GetFullPath($unresolved)
}

function New-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log "Created directory: $Path"
    } else {
        Write-Log "Directory exists: $Path"
    }
}

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Log "ERROR: $Message"
    throw $Message
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][string]$Description
    )

    Write-Log "Running: $Description"
    $output = & $ScriptBlock 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object {
        Write-Log ("  {0}" -f $_)
    }

    if ($exitCode -ne 0) {
        Fail "$Description failed with exit code $exitCode"
    }
}

function Invoke-Scoop {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
        Fail "Scoop command was not found: $script:ScoopPs1"
    }

    Invoke-LoggedCommand -Description ("scoop {0}" -f ($Arguments -join ' ')) -ScriptBlock ({
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScoopPs1 @Arguments
    }.GetNewClosure())
}

function Get-CommandOutput {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)

    $output = & $ScriptBlock 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Test-VersionLine {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    $result = Get-CommandOutput -ScriptBlock $ScriptBlock
    if ($result.ExitCode -ne 0) {
        Fail "$Name version check failed with exit code $($result.ExitCode): $($result.Output -join ' ')"
    }

    $text = ($result.Output -join "`n")
    Write-Log "$Name version output: $($text -replace "`r?`n", ' | ')"
    if ($text -notmatch [regex]::Escape($ExpectedVersion)) {
        Fail "$Name expected version $ExpectedVersion was not found in output: $text"
    }
}

function Backup-UserEnvironment {
    $names = @('Path', 'SCOOP', 'SCOOP_GLOBAL', 'SCOOP_CACHE')
    $backup = @{}
    foreach ($name in $names) {
        $backup[$name] = [Environment]::GetEnvironmentVariable($name, 'User')
    }
    return $backup
}

function Restore-UserEnvironment {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($name in $Backup.Keys) {
        $current = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($current -ne $Backup[$name]) {
            Write-Log "Restoring user environment variable: $name"
            [Environment]::SetEnvironmentVariable($name, $Backup[$name], 'User')
        }
    }
}

function Set-PortableProcessEnvironment {
    $env:SCOOP = $script:ScoopRoot
    $env:SCOOP_GLOBAL = $script:ScoopGlobalRoot
    $env:SCOOP_CACHE = Join-Path $script:CacheRoot 'scoop'
    $env:XDG_CONFIG_HOME = $script:ConfigRoot
    $env:HOME = $script:HomeRoot
    $env:USERPROFILE = $script:HomeRoot
    $env:APPDATA = Join-Path $script:AppDataRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $script:AppDataRoot 'Local'
    $env:TEMP = $script:TmpRoot
    $env:TMP = $script:TmpRoot
    $env:PIP_CONFIG_FILE = Join-Path $script:PipConfigRoot 'pip.ini'
    $env:PIP_CACHE_DIR = Join-Path $script:CacheRoot 'pip'
    $env:PYTHONUSERBASE = Join-Path $script:LocalRoot 'python-userbase'
    $env:npm_config_cache = Join-Path $script:CacheRoot 'npm'
    $env:npm_config_prefix = Join-Path $script:LocalRoot 'npm-prefix'
    $env:UV_CACHE_DIR = Join-Path $script:CacheRoot 'uv'

    $pathParts = @(
        (Join-Path $script:ScoopRoot 'shims'),
        (Join-Path $env:npm_config_prefix 'bin'),
        $env:Path
    ) | Where-Object { $_ }
    $env:Path = ($pathParts -join [IO.Path]::PathSeparator)
}

function Install-ScoopIfNeeded {
    if (Test-Path -LiteralPath $script:ScoopPs1) {
        Write-Log "Scoop already exists: $script:ScoopPs1"
        if ($Force) {
            Invoke-Scoop -Arguments @('update', 'scoop')
        }
        return
    }

    $installerPath = Join-Path $script:TmpRoot 'install-scoop.ps1'
    Write-Log "Downloading Scoop installer: $installerPath"
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $installerPath -UseBasicParsing

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-ScoopDir', $script:ScoopRoot,
        '-ScoopGlobalDir', $script:ScoopGlobalRoot,
        '-ScoopCacheDir', (Join-Path $script:CacheRoot 'scoop')
    )

    Invoke-LoggedCommand -Description 'install Scoop' -ScriptBlock ({
        & powershell.exe @args
    }.GetNewClosure())

    if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
        Fail "Scoop installation did not create $script:ScoopPs1"
    }
}

function Initialize-ScoopConfig {
    Invoke-Scoop -Arguments @('config', 'cache_path', (Join-Path $script:CacheRoot 'scoop'))
    Invoke-Scoop -Arguments @('config', 'show_update_log', 'false')

    Invoke-Scoop -Arguments @('bucket', 'known')
    $bucketList = Get-CommandOutput -ScriptBlock {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScoopPs1 bucket list
    }
    $bucketText = $bucketList.Output -join "`n"
    if ($bucketText -notmatch '(^|\s)extras(\s|$)') {
        Invoke-Scoop -Arguments @('bucket', 'add', 'extras')
    } else {
        Write-Log 'Scoop bucket exists: extras'
    }
}

function Install-ScoopAppVersion {
    param(
        [Parameter(Mandatory = $true)][string]$App,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $appRoot = Join-Path (Join-Path $script:ScoopRoot 'apps') $App
    $versionRoot = Join-Path $appRoot $Version
    if ((Test-Path -LiteralPath $versionRoot) -and (-not $Force)) {
        Write-Log "$App $Version already exists; reusing."
        Invoke-Scoop -Arguments @('reset', $App)
        return
    }

    if ((Test-Path -LiteralPath (Join-Path $appRoot 'current')) -and (-not (Test-Path -LiteralPath $versionRoot))) {
        Write-Log "$App is installed at a different version; uninstalling before installing $Version."
        Invoke-Scoop -Arguments @('uninstall', $App)
    } elseif ($Force -and (Test-Path -LiteralPath $appRoot)) {
        Write-Log "Force requested; uninstalling $App before reinstall."
        Invoke-Scoop -Arguments @('uninstall', $App)
    }

    Invoke-Scoop -Arguments @('install', "$App@$Version")
}

function Write-ConfigFiles {
    $pipIni = Join-Path $script:PipConfigRoot 'pip.ini'
    $pipCache = Join-Path $script:CacheRoot 'pip'
    if ((-not (Test-Path -LiteralPath $pipIni)) -or $Force) {
        @(
            '[global]',
            "cache-dir = $pipCache",
            'disable-pip-version-check = true'
        ) | Set-Content -LiteralPath $pipIni -Encoding UTF8
        Write-Log "Wrote pip config: $pipIni"
    }

    $npmrc = Join-Path $script:NpmConfigRoot 'npmrc'
    if ((-not (Test-Path -LiteralPath $npmrc)) -or $Force) {
        @(
            "cache=$($env:npm_config_cache)",
            "prefix=$($env:npm_config_prefix)"
        ) | Set-Content -LiteralPath $npmrc -Encoding UTF8
        Write-Log "Wrote npm config: $npmrc"
    }

    $uvConfig = Join-Path $script:UvConfigRoot 'uv.toml'
    if ((-not (Test-Path -LiteralPath $uvConfig)) -or $Force) {
        @(
            '# uv is configured through UV_CACHE_DIR in start.bat.',
            "# cache-dir = `"$($env:UV_CACHE_DIR.Replace('\', '\\'))`""
        ) | Set-Content -LiteralPath $uvConfig -Encoding UTF8
        Write-Log "Wrote uv config placeholder: $uvConfig"
    }
}

function Test-InstalledCommands {
    Test-VersionLine -Name 'VS Code' -ExpectedVersion $VscodeVersion -ScriptBlock { & code --version }
    Test-VersionLine -Name 'Python' -ExpectedVersion $PythonVersion -ScriptBlock { & python --version }
    Test-VersionLine -Name 'Node.js' -ExpectedVersion $NodejsVersion -ScriptBlock { & node --version }
    Test-VersionLine -Name 'uv' -ExpectedVersion $UvVersion -ScriptBlock { & uv --version }
    Test-VersionLine -Name 'jq' -ExpectedVersion $JqVersion -ScriptBlock { & jq --version }
    Test-VersionLine -Name 'pandoc' -ExpectedVersion $PandocVersion -ScriptBlock { & pandoc --version }

    $pipResult = Get-CommandOutput -ScriptBlock { & pip --version }
    if ($pipResult.ExitCode -ne 0) {
        Fail "pip version check failed with exit code $($pipResult.ExitCode): $($pipResult.Output -join ' ')"
    }
    Write-Log "pip version output: $($pipResult.Output -join ' | ')"
}

function Write-StartBatch {
    $batchPath = $script:StartBatFullPath
    $batchDir = Split-Path -Parent $batchPath
    New-Directory -Path $batchDir

    $content = @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "INSTALL_ROOT=%~dp0"
if "%INSTALL_ROOT:~-1%"=="\" set "INSTALL_ROOT=%INSTALL_ROOT:~0,-1%"

set "SCOOP=%INSTALL_ROOT%\.local\scoop"
set "SCOOP_GLOBAL=%INSTALL_ROOT%\.local\scoop-global"
set "SCOOP_CACHE=%INSTALL_ROOT%\.cache\scoop"
set "HOME=%INSTALL_ROOT%\.local\home"
set "USERPROFILE=%INSTALL_ROOT%\.local\home"
set "APPDATA=%INSTALL_ROOT%\.config\AppData\Roaming"
set "LOCALAPPDATA=%INSTALL_ROOT%\.config\AppData\Local"
set "TEMP=%INSTALL_ROOT%\.local\tmp"
set "TMP=%INSTALL_ROOT%\.local\tmp"
set "PIP_CONFIG_FILE=%INSTALL_ROOT%\.config\pip\pip.ini"
set "PIP_CACHE_DIR=%INSTALL_ROOT%\.cache\pip"
set "PYTHONUSERBASE=%INSTALL_ROOT%\.local\python-userbase"
set "npm_config_cache=%INSTALL_ROOT%\.cache\npm"
set "npm_config_prefix=%INSTALL_ROOT%\.local\npm-prefix"
set "UV_CACHE_DIR=%INSTALL_ROOT%\.cache\uv"
set "XDG_CONFIG_HOME=%INSTALL_ROOT%\.config"

set "PATH=%SCOOP%\shims;%npm_config_prefix%\bin;%PATH%"

for %%D in ("%HOME%" "%APPDATA%" "%LOCALAPPDATA%" "%TEMP%" "%PIP_CACHE_DIR%" "%npm_config_cache%" "%npm_config_prefix%" "%UV_CACHE_DIR%" "%INSTALL_ROOT%\.config\vscode\user-data" "%INSTALL_ROOT%\.config\vscode\extensions") do (
  if not exist "%%~D" mkdir "%%~D" >nul 2>nul
)

set "FAILED_REQUIRED=0"
for %%C in (code python pip node npm uv jq pandoc) do (
  set "FOUND="
  for /f "delims=" %%P in ('where %%C 2^>nul') do if not defined FOUND set "FOUND=%%P"
  if not defined FOUND (
    echo ERROR: %%C was not found on PATH.
    if /I "%%C"=="code" set "FAILED_REQUIRED=1"
    if /I "%%C"=="python" set "FAILED_REQUIRED=1"
    if /I "%%C"=="node" set "FAILED_REQUIRED=1"
  ) else (
    echo %%C: !FOUND!
    set "OUTSIDE=!FOUND:%INSTALL_ROOT%=!"
    if /I "!OUTSIDE!"=="!FOUND!" (
      echo WARNING: %%C resolved outside INSTALL_ROOT.
      if /I "%%C"=="code" set "FAILED_REQUIRED=1"
      if /I "%%C"=="python" set "FAILED_REQUIRED=1"
      if /I "%%C"=="node" set "FAILED_REQUIRED=1"
    )
  )
)

if not "%FAILED_REQUIRED%"=="0" (
  echo ERROR: required commands must resolve from %INSTALL_ROOT%.
  exit /b 1
)

code ^
  --user-data-dir "%INSTALL_ROOT%\.config\vscode\user-data" ^
  --extensions-dir "%INSTALL_ROOT%\.config\vscode\extensions" ^
  --no-sandbox ^
  --disable-gpu

exit /b %ERRORLEVEL%
'@

    Set-Content -LiteralPath $batchPath -Value $content -Encoding ASCII
    Write-Log "Wrote start batch: $batchPath"
}

$script:LogPath = $null
$userEnvBackup = $null

try {
    $script:InstallRootFullPath = Resolve-FullPath -Path $InstallRoot
    if (-not $StartBatPath) {
        $StartBatPath = Join-Path $script:InstallRootFullPath 'start.bat'
    }
    $script:StartBatFullPath = Resolve-FullPath -Path $StartBatPath

    $script:LocalRoot = Join-Path $script:InstallRootFullPath '.local'
    $script:ScoopRoot = Join-Path $script:LocalRoot 'scoop'
    $script:ScoopGlobalRoot = Join-Path $script:LocalRoot 'scoop-global'
    $script:LogsRoot = Join-Path $script:LocalRoot 'logs'
    $script:TmpRoot = Join-Path $script:LocalRoot 'tmp'
    $script:HomeRoot = Join-Path $script:LocalRoot 'home'
    $script:CacheRoot = Join-Path $script:InstallRootFullPath '.cache'
    $script:ConfigRoot = Join-Path $script:InstallRootFullPath '.config'
    $script:VscodeConfigRoot = Join-Path $script:ConfigRoot 'vscode'
    $script:PipConfigRoot = Join-Path $script:ConfigRoot 'pip'
    $script:NpmConfigRoot = Join-Path $script:ConfigRoot 'npm'
    $script:UvConfigRoot = Join-Path $script:ConfigRoot 'uv'
    $script:AppDataRoot = Join-Path $script:ConfigRoot 'AppData'
    $script:ScoopPs1 = Join-Path $script:ScoopRoot 'apps\scoop\current\bin\scoop.ps1'

    New-Item -ItemType Directory -Path $script:LogsRoot -Force | Out-Null
    $script:LogPath = Join-Path $script:LogsRoot ('create-pdev-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Log 'Create-Pdev started.'
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log "InstallRoot: $script:InstallRootFullPath"
    Write-Log "StartBatPath: $script:StartBatFullPath"
    Write-Log "Versions: Python=$PythonVersion Node.js=$NodejsVersion uv=$UvVersion jq=$JqVersion pandoc=$PandocVersion VSCode=$VscodeVersion"

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Fail 'PowerShell 5.1 or later is required.'
    }

    $directories = @(
        $script:InstallRootFullPath,
        $script:LocalRoot,
        $script:ScoopRoot,
        $script:ScoopGlobalRoot,
        $script:LogsRoot,
        $script:TmpRoot,
        $script:HomeRoot,
        $script:CacheRoot,
        (Join-Path $script:CacheRoot 'scoop'),
        (Join-Path $script:CacheRoot 'pip'),
        (Join-Path $script:CacheRoot 'npm'),
        (Join-Path $script:CacheRoot 'uv'),
        $script:ConfigRoot,
        $script:VscodeConfigRoot,
        (Join-Path $script:VscodeConfigRoot 'user-data'),
        (Join-Path $script:VscodeConfigRoot 'extensions'),
        $script:PipConfigRoot,
        $script:NpmConfigRoot,
        $script:UvConfigRoot,
        $script:AppDataRoot,
        (Join-Path $script:AppDataRoot 'Roaming'),
        (Join-Path $script:AppDataRoot 'Local'),
        (Join-Path $script:LocalRoot 'python-userbase'),
        (Join-Path $script:LocalRoot 'npm-prefix')
    )

    foreach ($directory in $directories) {
        New-Directory -Path $directory
    }

    Write-Log 'Checking network access to Scoop installer.'
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -Method Head -UseBasicParsing | Out-Null

    $userEnvBackup = Backup-UserEnvironment
    Set-PortableProcessEnvironment
    Write-ConfigFiles

    Install-ScoopIfNeeded
    Restore-UserEnvironment -Backup $userEnvBackup
    Set-PortableProcessEnvironment
    Initialize-ScoopConfig

    Install-ScoopAppVersion -App 'python' -Version $PythonVersion
    Install-ScoopAppVersion -App 'nodejs' -Version $NodejsVersion
    Install-ScoopAppVersion -App 'uv' -Version $UvVersion
    Install-ScoopAppVersion -App 'jq' -Version $JqVersion
    Install-ScoopAppVersion -App 'pandoc' -Version $PandocVersion
    Install-ScoopAppVersion -App 'vscode' -Version $VscodeVersion

    Set-PortableProcessEnvironment
    Test-InstalledCommands
    Write-StartBatch

    Write-Log 'Create-Pdev finished successfully.'
    exit 0
} catch {
    if ($script:LogPath) {
        Write-Log "Create-Pdev failed: $($_.Exception.Message)"
    } else {
        Write-Error $_
    }
    if ($userEnvBackup) {
        Restore-UserEnvironment -Backup $userEnvBackup
    }
    exit 1
}
