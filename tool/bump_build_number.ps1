<#
.SYNOPSIS
  Increments the build number (the "+N" suffix) in pubspec.yaml.
  Run this before every Windows build so the number shown on the home
  screen always reflects the most recently built binary.
#>

$ErrorActionPreference = 'Stop'

$pubspecPath = Join-Path $PSScriptRoot '..\pubspec.yaml'
$content = Get-Content -Path $pubspecPath -Raw

$pattern = '(?m)^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)'
$match = [regex]::Match($content, $pattern)
if (-not $match.Success) {
    throw "Could not find a 'version: X.Y.Z+N' line in $pubspecPath"
}

$versionName = $match.Groups[1].Value
$buildNumber = [int]$match.Groups[2].Value + 1
$newLine = "version: $versionName+$buildNumber"

$newContent = $content.Substring(0, $match.Index) + $newLine + $content.Substring($match.Index + $match.Length)
Set-Content -Path $pubspecPath -Value $newContent -NoNewline

Write-Host "Build number bumped to $buildNumber (version $versionName+$buildNumber)"
