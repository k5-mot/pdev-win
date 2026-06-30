[CmdletBinding()]
param(
  [string]$SetupPath = '',
  [string]$SetupMisePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
}

if ([string]::IsNullOrWhiteSpace($SetupPath)) {
  $SetupPath = Join-Path $PSScriptRoot '..\setup.ps1'
}
if ([string]::IsNullOrWhiteSpace($SetupMisePath)) {
  $SetupMisePath = Join-Path $PSScriptRoot '..\setup_mise.ps1'
}

function Get-FileText {
  param([Parameter(Mandatory)][string]$Path)

  $resolved = Resolve-Path -LiteralPath $Path
  return [IO.File]::ReadAllText($resolved)
}

function Get-SingleQuotedAssignment {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Name
  )

  $pattern = "(?m)^\s*(?:\[string\])?\`$$([regex]::Escape($Name))\s*=\s*'([^']+)'"
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) {
    throw "Could not find assignment: `$$Name"
  }
  return $match.Groups[1].Value
}

function Get-SetupPortableTools {
  param([Parameter(Mandatory)][string]$Text)

  $match = [regex]::Match($Text, "(?s)\`$DefaultPortableTools\s*=\s*@\((.*?)\r?\n\)")
  if (-not $match.Success) {
    throw 'Could not find $DefaultPortableTools.'
  }

  $tools = New-Object 'System.Collections.Generic.List[object]'
  $entryMatches = [regex]::Matches($match.Groups[1].Value, "\[ordered\]@\{\s*name='([^']+)';\s*repo='([^']+)';\s*tag='([^']+)';\s*assetName='([^']+)';\s*exeName='([^']+)';\s*shimName='([^']+)';\s*versionArgs=@\(([^)]*)\)\s*\}")
  foreach ($entry in $entryMatches) {
    $tools.Add([pscustomobject]@{
      name = $entry.Groups[1].Value
      repo = $entry.Groups[2].Value
      tag = $entry.Groups[3].Value
      assetName = $entry.Groups[4].Value
      exeName = $entry.Groups[5].Value
      shimName = $entry.Groups[6].Value
    }) | Out-Null
  }

  if ($tools.Count -eq 0) {
    throw 'Could not parse any $DefaultPortableTools entries.'
  }

  return $tools.ToArray()
}

function Add-PinnedRelease {
  param(
    [System.Collections.Generic.List[object]]$Pins,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$PinnedTag
  )

  if ($PinnedTag -in @('latest','stable')) {
    throw "$Source $Name must use a fixed tag, not '$PinnedTag'."
  }

  $Pins.Add([pscustomobject]@{
    Source = $Source
    Name = $Name
    Repo = $Repo
    PinnedTag = $PinnedTag
  }) | Out-Null
}

function Get-PinnedReleases {
  param(
    [Parameter(Mandatory)][string]$SetupText,
    [Parameter(Mandatory)][string]$SetupMiseText
  )

  $pins = New-Object 'System.Collections.Generic.List[object]'

  $setupUv = Get-SingleQuotedAssignment -Text $SetupText -Name 'UvVersion'
  Add-PinnedRelease $pins 'setup.ps1' 'uv' 'astral-sh/uv' $setupUv.TrimStart('v')

  $setupJq = Get-SingleQuotedAssignment -Text $SetupText -Name 'JqVersion'
  $setupJqTag = if ($setupJq.StartsWith('jq-')) { $setupJq } else { "jq-$setupJq" }
  Add-PinnedRelease $pins 'setup.ps1' 'jq' 'jqlang/jq' $setupJqTag

  $setupPandoc = Get-SingleQuotedAssignment -Text $SetupText -Name 'PandocVersion'
  Add-PinnedRelease $pins 'setup.ps1' 'pandoc' 'jgm/pandoc' $setupPandoc

  foreach ($tool in (Get-SetupPortableTools -Text $SetupText)) {
    Add-PinnedRelease $pins 'setup.ps1' $tool.name $tool.repo $tool.tag
  }

  $miseVersion = Get-SingleQuotedAssignment -Text $SetupMiseText -Name 'MiseVersion'
  Add-PinnedRelease $pins 'setup_mise.ps1' 'mise' 'jdx/mise' $miseVersion

  $miseUv = Get-SingleQuotedAssignment -Text $SetupMiseText -Name 'UvVersion'
  Add-PinnedRelease $pins 'setup_mise.ps1' 'uv' 'astral-sh/uv' $miseUv.TrimStart('v')

  $miseJq = Get-SingleQuotedAssignment -Text $SetupMiseText -Name 'JqVersion'
  $miseJqTag = if ($miseJq.StartsWith('jq-')) { $miseJq } else { "jq-$miseJq" }
  Add-PinnedRelease $pins 'setup_mise.ps1' 'jq' 'jqlang/jq' $miseJqTag

  $misePandoc = Get-SingleQuotedAssignment -Text $SetupMiseText -Name 'PandocVersion'
  Add-PinnedRelease $pins 'setup_mise.ps1' 'pandoc' 'jgm/pandoc' $misePandoc

  $miseToolMatches = [regex]::Matches($SetupMiseText, "Id='(?:aqua|github):([^']+)';\s*Version='([^']+)'")
  foreach ($match in $miseToolMatches) {
    $repo = $match.Groups[1].Value
    $tag = $match.Groups[2].Value
    $name = ($repo -split '/')[-1]
    Add-PinnedRelease $pins 'setup_mise.ps1' $name $repo $tag
  }

  $miseHttpToolMatches = [regex]::Matches($SetupMiseText, "Id='http:([^']+)';\s*Version='([^']+)';\s*Repo='([^']+)';\s*Tag='([^']+)'")
  foreach ($match in $miseHttpToolMatches) {
    $name = $match.Groups[1].Value
    $repo = $match.Groups[3].Value
    $tag = $match.Groups[4].Value
    Add-PinnedRelease $pins 'setup_mise.ps1' $name $repo $tag
  }

  return $pins.ToArray()
}

function Get-LatestReleaseTag {
  param([Parameter(Mandatory)][string]$Repo)

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $headers = @{
      Accept = 'application/vnd.github+json'
      'User-Agent' = 'pdev-win-version-check'
      Authorization = "Bearer $env:GITHUB_TOKEN"
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -UseBasicParsing
    return [string]$release.tag_name
  }

  $latestUri = "https://github.com/$Repo/releases/latest"
  try {
    $request = [Net.WebRequest]::Create($latestUri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'pdev-win-version-check'
    $response = $request.GetResponse()
    try {
      $location = [string]$response.Headers['Location']
      if ([string]::IsNullOrWhiteSpace($location)) {
        $location = [string]$response.ResponseUri.AbsoluteUri
      }

      $match = [regex]::Match($location, '/releases/tag/([^/?#]+)')
      if ($match.Success) {
        return [uri]::UnescapeDataString($match.Groups[1].Value)
      }
    } finally {
      $response.Close()
    }
  } catch {
  }

  throw "Could not resolve the latest GitHub release tag from releases/latest redirect: $Repo"
}

$setupText = Get-FileText -Path $SetupPath
$setupMiseText = Get-FileText -Path $SetupMisePath
$pins = Get-PinnedReleases -SetupText $setupText -SetupMiseText $setupMiseText

$latestByRepo = @{}
$outdated = New-Object 'System.Collections.Generic.List[object]'

foreach ($pin in $pins) {
  if (-not $latestByRepo.ContainsKey($pin.Repo)) {
    $latestByRepo[$pin.Repo] = Get-LatestReleaseTag -Repo $pin.Repo
  }

  $latest = $latestByRepo[$pin.Repo]
  if ($pin.PinnedTag -ne $latest) {
    $outdated.Add([pscustomobject]@{
      Source = $pin.Source
      Name = $pin.Name
      Repo = $pin.Repo
      PinnedTag = $pin.PinnedTag
      LatestTag = $latest
    }) | Out-Null
  }
}

if ($outdated.Count -gt 0) {
  foreach ($item in $outdated) {
    $message = "{0} {1} pins {2}@{3}, latest is {4}." -f $item.Source, $item.Name, $item.Repo, $item.PinnedTag, $item.LatestTag
    Write-Host "::error title=Outdated pinned release::$message"
    Write-Error $message
  }
  throw "Outdated pinned GitHub release versions found: $($outdated.Count)"
}

foreach ($pin in $pins) {
  Write-Host ("OK {0} {1}: {2}@{3}" -f $pin.Source, $pin.Name, $pin.Repo, $pin.PinnedTag)
}
