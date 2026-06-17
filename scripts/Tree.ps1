<#
.SYNOPSIS
指定したディレクトリ配下のディレクトリツリーを表示します。
.PARAMETER Path
表示対象のルートディレクトリです。
.PARAMETER Depth
表示する階層の深さです。
.EXAMPLE
.\Tree.ps1 -Path . -Depth 2
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Convert-Path .),

    [Parameter()]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$Depth = 99
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
指定した階層のインデント文字列を作成します。
.PARAMETER Level
インデント階層です。
.OUTPUTS
インデント文字列を返します。
#>
function New-TreeIndent {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Level
    )

    return ("  " * $Level)
}

<#
.SYNOPSIS
ディレクトリツリーを再帰的に表示します。
.PARAMETER CurrentPath
現在表示しているディレクトリです。
.PARAMETER Level
現在の階層です。
.PARAMETER MaxDepth
表示する最大階層です。
#>
function Write-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentPath,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxDepth
    )

    if ($Level -gt $MaxDepth) {
        return
    }

    $name = Split-Path -Leaf $CurrentPath
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $CurrentPath
    }

    Write-Host ("{0}{1}" -f (New-TreeIndent -Level $Level), $name)

    if ($Level -eq $MaxDepth) {
        return
    }

    Get-ChildItem -LiteralPath $CurrentPath -Force -Directory |
        Sort-Object Name |
        ForEach-Object {
            Write-DirectoryTree -CurrentPath $_.FullName -Level ($Level + 1) -MaxDepth $MaxDepth
        }
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path

Write-Host ""
Write-Host "---------------------------------------"
Write-Host ("対象パス: {0}" -f $resolvedPath)
Write-Host ("深さ: {0}" -f $Depth)
Write-Host "---------------------------------------"
Write-DirectoryTree -CurrentPath $resolvedPath -Level 0 -MaxDepth $Depth
Write-Host "---------------------------------------"
