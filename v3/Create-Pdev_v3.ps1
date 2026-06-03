param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot,

    [string]$PythonVersion = '3.12.10',
    [string]$NodejsVersion = '22.16.0',
    [string]$UvVersion = '0.7.8',
    [string]$JqVersion = '1.7.1',
    [string]$PandocVersion = '3.7.0.2',
    [string]$VscodeVersion = '1.121.0',
    [string[]]$AdditionalTools = @('ripgrep', 'fd', 'bat', 'delta', 'curl', 'lazygit', 'neovim', 'yq', 'hyperfine', 'rustup'),
    [string]$StartBatPath,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    <#
        .SYNOPSIS
        Resolves a possibly non-existing path to a full filesystem path.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $unresolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    return [System.IO.Path]::GetFullPath($unresolved)
}

function Write-Log {
    <#
        .SYNOPSIS
        Writes a timestamped, colored message to the console and log file.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Install', 'Download', 'CacheHit', 'Error', 'Success', 'Verify')]
        [string]$Level = 'Info'
    )

    $meta = @{
        Info = @{ Prefix = 'ℹ [Info]'; Color = 'Cyan' }
        Install = @{ Prefix = '⚙ [Install]'; Color = 'Yellow' }
        Download = @{ Prefix = '↓ [Download]'; Color = 'Magenta' }
        CacheHit = @{ Prefix = '✓ [CacheHit]'; Color = 'Green' }
        Error = @{ Prefix = '✗ [Error]'; Color = 'Red' }
        Success = @{ Prefix = '✓ [Success]'; Color = 'Green' }
        Verify = @{ Prefix = '○ [Verify]'; Color = 'Blue' }
    }

    $line = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $meta[$Level].Prefix, $Message
    Write-Host $line -ForegroundColor $meta[$Level].Color
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
}

function New-Directory {
    <#
        .SYNOPSIS
        Creates a directory if it does not already exist.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log -Level 'Info' -Message "Created directory: $Path"
    } else {
        Write-Log -Level 'CacheHit' -Message "Directory exists: $Path"
    }
}

function Fail {
    <#
        .SYNOPSIS
        Logs an error message and throws it.
    #>
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Log -Level 'Error' -Message $Message
    throw $Message
}

function Invoke-LoggedCommand {
    <#
        .SYNOPSIS
        Runs an external command scriptblock and streams its output to the console and log.
    #>
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][string]$Description
    )

    Write-Log -Level 'Install' -Message "Running: $Description"
    & $ScriptBlock 2>&1 | ForEach-Object {
        Write-Log -Level 'Info' -Message ("  {0}" -f $_)
    }
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Fail "$Description failed with exit code $exitCode"
    }
}

function Invoke-Scoop {
    <#
        .SYNOPSIS
        Runs the portable Scoop command with the supplied arguments.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
        Fail "Scoop command was not found: $script:ScoopPs1"
    }

    $scoopPs1 = $script:ScoopPs1
    $scoopArguments = $Arguments
    Invoke-LoggedCommand -Description ("scoop {0}" -f ($Arguments -join ' ')) -ScriptBlock ({
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scoopPs1 @scoopArguments
    }.GetNewClosure())
}

function Get-CommandOutput {
    <#
        .SYNOPSIS
        Captures command output and exit code from a scriptblock.
    #>
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $ScriptBlock 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @($_.Exception.Message, ($_ | Out-String))
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Test-ScoopAppInstalled {
    <#
        .SYNOPSIS
        Returns true when an app has a current link to the requested version and required files.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$App,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $appRoot = Join-Path (Join-Path $script:ScoopRoot 'apps') $App
    $versionRoot = Join-Path $appRoot $Version
    $currentRoot = Join-Path $appRoot 'current'

    if ((-not (Test-Path -LiteralPath $versionRoot)) -or (-not (Test-Path -LiteralPath $currentRoot))) {
        return $false
    }

    $currentItem = Get-Item -LiteralPath $currentRoot -Force
    $target = @($currentItem.Target) | Select-Object -First 1
    if (-not $target) {
        return $false
    }

    $expected = [System.IO.Path]::GetFullPath($versionRoot).TrimEnd('\')
    $actual = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
    if ($actual -ine $expected) {
        return $false
    }

    $requiredFiles = switch ($App) {
        'python' { @('python.exe', 'Scripts\pip.exe') }
        'nodejs' { @('node.exe', 'npm.cmd') }
        'uv' { @('uv.exe') }
        'jq' { @('jq.exe') }
        'pandoc' { @('pandoc.exe') }
        'vscode' { @('Code.exe', 'bin\code.cmd') }
        default { @() }
    }

    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $currentRoot $relativePath))) {
            return $false
        }
    }

    return $true
}

function Test-VersionLine {
    <#
        .SYNOPSIS
        Verifies that a command version output contains the expected version.
    #>
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
    Write-Log -Level 'Verify' -Message "$Name version output: $($text -replace "`r?`n", ' | ')"
    if ($text -notmatch [regex]::Escape($ExpectedVersion)) {
        Fail "$Name expected version $ExpectedVersion was not found in output: $text"
    }
}

function Test-CommandVersion {
    <#
        .SYNOPSIS
        Verifies that a command resolves under InstallRoot and prints a version.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command
    )

    try {
        $resolved = Get-Command $Command -ErrorAction Stop | Select-Object -First 1
        $source = [string]$resolved.Source
        if (-not $source) {
            Fail "$Name command did not provide a source path: $Command"
        }

        if (-not $source.StartsWith($script:InstallRootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "$Name resolved outside InstallRoot: $source"
        }
    } catch {
        Fail "$Name command resolution failed for ${Command}: $($_.Exception.Message)"
    }

    $commandPath = $source
    $result = Get-CommandOutput -ScriptBlock {
        & $commandPath --version
    }
    if ($result.ExitCode -ne 0) {
        Fail "$Name version check failed with exit code $($result.ExitCode): $($result.Output -join ' ')"
    }

    Write-Log -Level 'Verify' -Message "$Name version output: $(($result.Output | Select-Object -First 3) -join ' | ')"
}

function Backup-UserEnvironment {
    <#
        .SYNOPSIS
        Captures user-level environment variables that Scoop installers may change.
    #>
    $names = @('Path', 'SCOOP', 'SCOOP_GLOBAL', 'SCOOP_CACHE')
    $backup = @{}
    foreach ($name in $names) {
        $backup[$name] = [Environment]::GetEnvironmentVariable($name, 'User')
    }
    return $backup
}

function Restore-UserEnvironment {
    <#
        .SYNOPSIS
        Restores user-level environment variables from a backup.
    #>
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($name in $Backup.Keys) {
        $current = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($current -ne $Backup[$name]) {
            Write-Log -Level 'Info' -Message "Restoring user environment variable: $name"
            [Environment]::SetEnvironmentVariable($name, $Backup[$name], 'User')
        }
    }
}

function Set-PortableProcessEnvironment {
    <#
        .SYNOPSIS
        Points process-scoped tool, config, cache, temp, and PowerShell cache paths under InstallRoot.
    #>
    $env:SCOOP = $script:ScoopRoot
    $env:SCOOP_GLOBAL = $script:ScoopGlobalRoot
    $env:SCOOP_CACHE = Join-Path $script:CacheRoot 'scoop'
    $env:SCOOP_STARTMENU_DIR = $script:ScoopStartMenuRoot
    $env:XDG_CONFIG_HOME = $script:ConfigRoot
    $env:HOME = $script:HomeRoot
    $env:USERPROFILE = $script:HomeRoot
    $homeRootPath = [System.IO.Path]::GetFullPath($script:HomeRoot)
    $env:HOMEDRIVE = [System.IO.Path]::GetPathRoot($homeRootPath).TrimEnd('\')
    $env:HOMEPATH = $homeRootPath.Substring($env:HOMEDRIVE.Length)
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
    $env:CARGO_HOME = Join-Path $script:ScoopRoot 'persist\rustup\.cargo'
    $env:RUSTUP_HOME = Join-Path $script:ScoopRoot 'persist\rustup\.rustup'
    $env:PSModuleAnalysisCachePath = Join-Path $script:CacheRoot 'powershell\ModuleAnalysisCache'

    $pathParts = @(
        (Join-Path $script:ScoopRoot 'shims'),
        (Join-Path $env:CARGO_HOME 'bin'),
        (Join-Path $script:ScoopRoot 'apps\vscode\current\bin'),
        (Join-Path $script:ScoopRoot 'apps\vscode\current'),
        (Join-Path $script:ScoopRoot 'apps\python\current\Scripts'),
        (Join-Path $script:ScoopRoot 'apps\python\current'),
        (Join-Path $script:ScoopRoot 'apps\nodejs\current\bin'),
        (Join-Path $script:ScoopRoot 'apps\nodejs\current'),
        (Join-Path $env:npm_config_prefix 'bin'),
        $env:Path
    ) | Where-Object { $_ }
    $env:Path = ($pathParts -join [IO.Path]::PathSeparator)
}

function Repair-RustupInstall {
    <#
        .SYNOPSIS
        Repairs a rustup install that completed persist data but stopped before Scoop linked it.
    #>
    $appRoot = Join-Path (Join-Path $script:ScoopRoot 'apps') 'rustup'
    $versionRoot = Join-Path $appRoot '1.29.0'
    $currentRoot = Join-Path $appRoot 'current'
    $rustupExe = Join-Path $env:CARGO_HOME 'bin\rustup.exe'

    if ((Test-Path -LiteralPath $currentRoot) -or (-not (Test-Path -LiteralPath $versionRoot)) -or (-not (Test-Path -LiteralPath $rustupExe))) {
        return $false
    }

    Write-Log -Level 'Install' -Message 'Repairing partial rustup installation.'
    if (-not (Test-Path -LiteralPath $currentRoot)) {
        New-Item -ItemType Junction -Path $currentRoot -Target $versionRoot -Force | Out-Null
    }
    return $true
}

function Test-RustupAvailable {
    <#
        .SYNOPSIS
        Returns true when the portable rustup/cargo binaries exist under InstallRoot.
    #>
    $requiredFiles = @(
        (Join-Path $env:CARGO_HOME 'bin\rustup.exe'),
        (Join-Path $env:CARGO_HOME 'bin\rustc.exe'),
        (Join-Path $env:CARGO_HOME 'bin\cargo.exe')
    )

    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            return $false
        }
    }

    return $true
}

function Update-ScoopShortcutRoot {
    <#
        .SYNOPSIS
        Patches the portable Scoop shortcut helper to use SCOOP_STARTMENU_DIR when set.
    #>
    $shortcutLib = Join-Path $script:ScoopRoot 'apps\scoop\current\lib\shortcuts.ps1'
    if (-not (Test-Path -LiteralPath $shortcutLib)) {
        Fail "Scoop shortcut helper was not found: $shortcutLib"
    }

    $text = Get-Content -Raw -LiteralPath $shortcutLib
    if ($text -match [regex]::Escape('$env:SCOOP_STARTMENU_DIR')) {
        Write-Log -Level 'CacheHit' -Message "Scoop shortcut root patch already exists: $shortcutLib"
        return
    }

    $new = @'
function shortcut_folder($global) {
    if (!$global -and $env:SCOOP_STARTMENU_DIR) {
        return Convert-Path (ensure $env:SCOOP_STARTMENU_DIR)
    }
    if ($global) {
        $startmenu = 'CommonStartMenu'
    } else {
        $startmenu = 'StartMenu'
    }
    return Convert-Path (ensure ([System.IO.Path]::Combine([Environment]::GetFolderPath($startmenu), 'Programs', 'Scoop Apps')))
}
'@

    $pattern = '(?s)function shortcut_folder\(\$global\) \{.*?return Convert-Path \(ensure \(\[System\.IO\.Path\]::Combine\(\[Environment\]::GetFolderPath\(\$startmenu\), ''Programs'', ''Scoop Apps''\)\)\)\s*\}'
    if ($text -notmatch $pattern) {
        Fail "Scoop shortcut helper did not match the expected format: $shortcutLib"
    }

    [regex]::Replace($text, $pattern, $new, 1) | Set-Content -LiteralPath $shortcutLib -Encoding ASCII
    Write-Log -Level 'Info' -Message "Patched Scoop shortcut root: $shortcutLib"
}

function Move-PortableScoopShortcuts {
    <#
        .SYNOPSIS
        Moves existing Scoop shortcuts that target InstallRoot into the portable Start Menu directory.
    #>
    $candidateRoots = @()
    $startMenuRoot = [Environment]::GetFolderPath('StartMenu')
    if (-not [string]::IsNullOrWhiteSpace($startMenuRoot)) {
        $candidateRoots += Join-Path $startMenuRoot 'Programs\Scoop Apps'
    }

    $workingDirectory = (Get-Location).Path
    if (-not [string]::IsNullOrWhiteSpace($workingDirectory)) {
        $candidateRoots += Join-Path $workingDirectory 'Programs\Scoop Apps'
    }

    $candidateRoots = $candidateRoots | Select-Object -Unique

    $shell = New-Object -ComObject WScript.Shell
    foreach ($candidateRoot in $candidateRoots) {
        if ((-not $candidateRoot) -or (-not (Test-Path -LiteralPath $candidateRoot))) {
            continue
        }

        if ([System.IO.Path]::GetFullPath($candidateRoot).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($script:ScoopStartMenuRoot).TrimEnd('\')) {
            continue
        }

        Get-ChildItem -LiteralPath $candidateRoot -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $shortcut = $shell.CreateShortcut($_.FullName)
            if ($shortcut.TargetPath -and $shortcut.TargetPath.StartsWith($script:InstallRootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativePath = $_.FullName.Substring($candidateRoot.Length).TrimStart('\')
                $destination = Join-Path $script:ScoopStartMenuRoot $relativePath
                New-Directory -Path (Split-Path -Parent $destination)
                Move-Item -LiteralPath $_.FullName -Destination $destination -Force
                Write-Log -Level 'Info' -Message "Moved Scoop shortcut into InstallRoot: $destination"
            }
        }
    }
}

function Install-ScoopIfNeeded {
    <#
        .SYNOPSIS
        Downloads and installs Scoop into the portable root when absent.
    #>
    if (Test-Path -LiteralPath $script:ScoopPs1) {
        Write-Log -Level 'CacheHit' -Message "Scoop already exists: $script:ScoopPs1"
        if ($Force) {
            Invoke-Scoop -Arguments @('update', 'scoop')
        }
        return
    }

    $installerPath = Join-Path $script:TmpRoot 'install-scoop.ps1'
    Write-Log -Level 'Download' -Message "Downloading Scoop installer: $installerPath"
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $installerPath -UseBasicParsing

    $installerArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath,
        '-ScoopDir', $script:ScoopRoot,
        '-ScoopGlobalDir', $script:ScoopGlobalRoot,
        '-ScoopCacheDir', (Join-Path $script:CacheRoot 'scoop')
    )

    Invoke-LoggedCommand -Description 'install Scoop' -ScriptBlock ({
        & powershell.exe @installerArgs
    }.GetNewClosure())

    if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
        Fail "Scoop installation did not create $script:ScoopPs1"
    }
}

function Initialize-ScoopConfig {
    <#
        .SYNOPSIS
        Configures portable Scoop settings and required buckets.
    #>
    Invoke-Scoop -Arguments @('config', 'cache_path', (Join-Path $script:CacheRoot 'scoop'))
    Invoke-Scoop -Arguments @('config', 'show_update_log', 'false')

    $bucketList = Get-CommandOutput -ScriptBlock {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ScoopPs1 bucket list
    }
    $bucketText = $bucketList.Output -join "`n"
    if ($bucketText -notmatch '(^|\s)extras(\s|$)') {
        Invoke-Scoop -Arguments @('bucket', 'add', 'extras')
    } else {
        Write-Log -Level 'CacheHit' -Message 'Scoop bucket exists: extras'
    }
}

function Install-ScoopAppVersion {
    <#
        .SYNOPSIS
        Installs or switches a Scoop app to the requested version.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$App,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if ((Test-ScoopAppInstalled -App $App -Version $Version) -and (-not $Force)) {
        Write-Log -Level 'CacheHit' -Message "$App $Version is installed; reusing."
        Invoke-Scoop -Arguments @('reset', $App)
        return
    }

    $appRoot = Join-Path (Join-Path $script:ScoopRoot 'apps') $App
    $currentRoot = Join-Path $appRoot 'current'
    $versionRoot = Join-Path $appRoot $Version

    if ((Test-Path -LiteralPath $appRoot) -and (-not (Test-Path -LiteralPath $currentRoot))) {
        $appsRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ScoopRoot 'apps')).TrimEnd('\')
        $resolvedAppRoot = [System.IO.Path]::GetFullPath($appRoot).TrimEnd('\')
        if ($resolvedAppRoot.StartsWith($appsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Log -Level 'Install' -Message "$App has an incomplete app directory; removing it before installing $Version."
            Remove-Item -LiteralPath $appRoot -Recurse -Force
        } else {
            Fail "Refusing to remove app directory outside Scoop apps root: $appRoot"
        }
    } elseif ((Test-Path -LiteralPath $appRoot) -and (-not (Test-ScoopAppInstalled -App $App -Version $Version))) {
        Write-Log -Level 'Install' -Message "$App has an incomplete or different installation; uninstalling before installing $Version."
        Invoke-Scoop -Arguments @('uninstall', $App)
    }

    if ((Test-Path -LiteralPath $currentRoot) -and (-not (Test-Path -LiteralPath $versionRoot))) {
        Write-Log -Level 'Install' -Message "$App is installed at a different version; uninstalling before installing $Version."
        Invoke-Scoop -Arguments @('uninstall', $App)
    } elseif ($Force -and (Test-Path -LiteralPath $appRoot)) {
        Write-Log -Level 'Install' -Message "Force requested; uninstalling $App before reinstall."
        Invoke-Scoop -Arguments @('uninstall', $App)
    }

    Invoke-Scoop -Arguments @('install', "$App@$Version")
}

function Install-ScoopAppLatest {
    <#
        .SYNOPSIS
        Installs a Scoop app at the current bucket version, or reuses it when present.
    #>
    param([Parameter(Mandatory = $true)][string]$App)

    if (($App -eq 'rustup') -and (Test-RustupAvailable) -and (-not $Force)) {
        Write-Log -Level 'CacheHit' -Message 'rustup toolchain is available; reusing.'
        return
    }

    if (($App -eq 'rustup') -and (Repair-RustupInstall) -and (-not $Force)) {
        Write-Log -Level 'CacheHit' -Message 'rustup partial installation was repaired; reusing.'
        return
    }

    $appRoot = Join-Path (Join-Path $script:ScoopRoot 'apps') $App
    $currentRoot = Join-Path $appRoot 'current'

    if ((Test-Path -LiteralPath $currentRoot) -and (-not $Force)) {
        Write-Log -Level 'CacheHit' -Message "$App is installed; reusing."
        Invoke-Scoop -Arguments @('reset', $App)
        return
    }

    if ((Test-Path -LiteralPath $appRoot) -and (-not (Test-Path -LiteralPath $currentRoot))) {
        $appsRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ScoopRoot 'apps')).TrimEnd('\')
        $resolvedAppRoot = [System.IO.Path]::GetFullPath($appRoot).TrimEnd('\')
        if ($resolvedAppRoot.StartsWith($appsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Log -Level 'Install' -Message "$App has an incomplete app directory; removing it before installing."
            Remove-Item -LiteralPath $appRoot -Recurse -Force
        } else {
            Fail "Refusing to remove app directory outside Scoop apps root: $appRoot"
        }
    } elseif ($Force -and (Test-Path -LiteralPath $appRoot)) {
        Write-Log -Level 'Install' -Message "Force requested; uninstalling $App before reinstall."
        Invoke-Scoop -Arguments @('uninstall', $App)
    }

    Invoke-Scoop -Arguments @('install', $App)
}

function Write-ConfigFiles {
    <#
        .SYNOPSIS
        Writes portable pip, npm, and uv configuration files.
    #>
    $pipIni = Join-Path $script:PipConfigRoot 'pip.ini'
    $pipCache = Join-Path $script:CacheRoot 'pip'
    @(
        '[global]',
        "cache-dir = $pipCache",
        'disable-pip-version-check = true'
    ) | Set-Content -LiteralPath $pipIni -Encoding ASCII
    Write-Log -Level 'Info' -Message "Wrote pip config: $pipIni"

    $npmrc = Join-Path $script:NpmConfigRoot 'npmrc'
    @(
        "cache=$($env:npm_config_cache)",
        "prefix=$($env:npm_config_prefix)"
    ) | Set-Content -LiteralPath $npmrc -Encoding ASCII
    Write-Log -Level 'Info' -Message "Wrote npm config: $npmrc"

    $uvConfig = Join-Path $script:UvConfigRoot 'uv.toml'
    @(
        '# uv is configured through UV_CACHE_DIR in start.bat.',
        "# cache-dir = `"$($env:UV_CACHE_DIR.Replace('\', '\\'))`""
    ) | Set-Content -LiteralPath $uvConfig -Encoding ASCII
    Write-Log -Level 'Info' -Message "Wrote uv config placeholder: $uvConfig"
}

function Test-InstalledCommands {
    <#
        .SYNOPSIS
        Verifies installed command versions from the portable PATH.
    #>
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
    Write-Log -Level 'Verify' -Message "pip version output: $($pipResult.Output -join ' | ')"

    $additionalCommandChecks = @(
        @{ Name = 'ripgrep'; Command = 'rg' },
        @{ Name = 'fd'; Command = 'fd' },
        @{ Name = 'bat'; Command = 'bat' },
        @{ Name = 'delta'; Command = 'delta' },
        @{ Name = 'curl'; Command = 'curl.exe' },
        @{ Name = 'lazygit'; Command = 'lazygit' },
        @{ Name = 'neovim'; Command = 'nvim' },
        @{ Name = 'yq'; Command = 'yq' },
        @{ Name = 'hyperfine'; Command = 'hyperfine' },
        @{ Name = 'rustup'; Command = 'rustup' }
    )

    foreach ($check in ($additionalCommandChecks | Where-Object { $AdditionalTools -contains $_.Name })) {
        Test-CommandVersion -Name $check.Name -Command $check.Command
    }
}

function Write-StartBatch {
    <#
        .SYNOPSIS
        Generates start.bat with portable environment variables and PATH checks.
    #>
    $batchPath = $script:StartBatFullPath
    $batchDir = Split-Path -Parent $batchPath
    New-Directory -Path $batchDir

    $escapedInstallRoot = $script:InstallRootFullPath
    $content = @"
@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "INSTALL_ROOT=$escapedInstallRoot"

set "SCOOP=%INSTALL_ROOT%\.local\scoop"
set "SCOOP_GLOBAL=%INSTALL_ROOT%\.local\scoop-global"
set "SCOOP_CACHE=%INSTALL_ROOT%\.cache\scoop"
set "SCOOP_STARTMENU_DIR=%INSTALL_ROOT%\.config\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps"
set "HOME=%INSTALL_ROOT%\.local\home"
set "USERPROFILE=%INSTALL_ROOT%\.local\home"
for %%I in ("%USERPROFILE%") do (
  set "HOMEDRIVE=%%~dI"
  set "HOMEPATH=%%~pnxI"
)
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
set "CARGO_HOME=%INSTALL_ROOT%\.local\scoop\persist\rustup\.cargo"
set "RUSTUP_HOME=%INSTALL_ROOT%\.local\scoop\persist\rustup\.rustup"
set "PSModuleAnalysisCachePath=%INSTALL_ROOT%\.cache\powershell\ModuleAnalysisCache"
set "XDG_CONFIG_HOME=%INSTALL_ROOT%\.config"

set "PATH=%SCOOP%\shims;%CARGO_HOME%\bin;%SCOOP%\apps\vscode\current\bin;%SCOOP%\apps\vscode\current;%SCOOP%\apps\python\current\Scripts;%SCOOP%\apps\python\current;%SCOOP%\apps\nodejs\current\bin;%SCOOP%\apps\nodejs\current;%npm_config_prefix%\bin;%PATH%"

for %%D in ("%HOME%" "%HOME%\AppData\Local" "%HOME%\AppData\Roaming" "%APPDATA%" "%LOCALAPPDATA%" "%TEMP%" "%PIP_CACHE_DIR%" "%npm_config_cache%" "%npm_config_prefix%" "%UV_CACHE_DIR%" "%CARGO_HOME%" "%RUSTUP_HOME%" "%SCOOP_STARTMENU_DIR%" "%INSTALL_ROOT%\.cache\powershell" "%INSTALL_ROOT%\.config\vscode\user-data" "%INSTALL_ROOT%\.config\vscode\extensions") do (
  if not exist "%%~D" mkdir "%%~D" >nul 2>nul
)

set "FAILED_REQUIRED=0"
for %%C in (code python pip node npm uv jq pandoc rg fd bat delta curl lazygit nvim yq hyperfine rustup) do (
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

start "" "%SCOOP%\apps\vscode\current\Code.exe" ^
  --user-data-dir "%INSTALL_ROOT%\.config\vscode\user-data" ^
  --extensions-dir "%INSTALL_ROOT%\.config\vscode\extensions" ^
  --no-sandbox ^
  --disable-gpu

exit /b 0
"@

    Set-Content -LiteralPath $batchPath -Value $content -Encoding ASCII
    Write-Log -Level 'Success' -Message "Wrote start batch: $batchPath"
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
    $script:ScoopStartMenuRoot = Join-Path $script:AppDataRoot 'Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps'
    $script:ScoopPs1 = Join-Path $script:ScoopRoot 'apps\scoop\current\bin\scoop.ps1'

    New-Item -ItemType Directory -Path $script:LogsRoot -Force | Out-Null
    $script:LogPath = Join-Path $script:LogsRoot ('create-pdev-v3-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Log -Level 'Info' -Message 'Create-Pdev_v3 started.'
    Write-Log -Level 'Info' -Message "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log -Level 'Info' -Message "OS: $([Environment]::OSVersion.VersionString)"
    Write-Log -Level 'Info' -Message "InstallRoot: $script:InstallRootFullPath"
    Write-Log -Level 'Info' -Message "StartBatPath: $script:StartBatFullPath"
    Write-Log -Level 'Info' -Message "Versions: Python=$PythonVersion Node.js=$NodejsVersion uv=$UvVersion jq=$JqVersion pandoc=$PandocVersion VSCode=$VscodeVersion"
    Write-Log -Level 'Info' -Message "Additional tools: $($AdditionalTools -join ', ')"

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
        (Join-Path $script:HomeRoot 'AppData'),
        (Join-Path $script:HomeRoot 'AppData\Local'),
        (Join-Path $script:HomeRoot 'AppData\Roaming'),
        $script:CacheRoot,
        (Join-Path $script:CacheRoot 'scoop'),
        (Join-Path $script:CacheRoot 'pip'),
        (Join-Path $script:CacheRoot 'npm'),
        (Join-Path $script:CacheRoot 'uv'),
        (Join-Path $script:CacheRoot 'powershell'),
        $script:ConfigRoot,
        $script:VscodeConfigRoot,
        (Join-Path $script:VscodeConfigRoot 'user-data'),
        (Join-Path $script:VscodeConfigRoot 'extensions'),
        $script:PipConfigRoot,
        $script:NpmConfigRoot,
        $script:UvConfigRoot,
        $script:AppDataRoot,
        (Join-Path $script:AppDataRoot 'Roaming'),
        $script:ScoopStartMenuRoot,
        (Join-Path $script:AppDataRoot 'Local'),
        (Join-Path $script:LocalRoot 'python-userbase'),
        (Join-Path $script:LocalRoot 'npm-prefix')
    )

    foreach ($directory in $directories) {
        New-Directory -Path $directory
    }

    Set-PortableProcessEnvironment
    Write-Log -Level 'Verify' -Message "PowerShell module analysis cache: $env:PSModuleAnalysisCachePath"
    Write-Log -Level 'Verify' -Message 'Checking network access to Scoop installer.'
    Invoke-WebRequest -Uri 'https://get.scoop.sh' -Method Head -UseBasicParsing | Out-Null

    $userEnvBackup = Backup-UserEnvironment
    Write-ConfigFiles

    Install-ScoopIfNeeded
    Restore-UserEnvironment -Backup $userEnvBackup
    Set-PortableProcessEnvironment
    Update-ScoopShortcutRoot
    Move-PortableScoopShortcuts
    Initialize-ScoopConfig

    Install-ScoopAppVersion -App 'python' -Version $PythonVersion
    Install-ScoopAppVersion -App 'nodejs' -Version $NodejsVersion
    Install-ScoopAppVersion -App 'uv' -Version $UvVersion
    Install-ScoopAppVersion -App 'jq' -Version $JqVersion
    Install-ScoopAppVersion -App 'pandoc' -Version $PandocVersion
    Install-ScoopAppVersion -App 'vscode' -Version $VscodeVersion
    foreach ($tool in $AdditionalTools) {
        Install-ScoopAppLatest -App $tool
    }

    Set-PortableProcessEnvironment
    Move-PortableScoopShortcuts
    Test-InstalledCommands
    Write-StartBatch

    Write-Log -Level 'Success' -Message 'Create-Pdev_v3 finished successfully.'
    exit 0
} catch {
    if ($script:LogPath) {
        Write-Log -Level 'Error' -Message "Create-Pdev_v3 failed: $($_.Exception.Message)"
    } else {
        Write-Error $_
    }
    if ($userEnvBackup) {
        Restore-UserEnvironment -Backup $userEnvBackup
    }
    exit 1
}
