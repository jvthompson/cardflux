<#
.SYNOPSIS
  Builds, packages, and publishes a new Cardflux GitHub Release.
  Bumps the build number, builds the Windows release binary, zips it as
  cardflux-windows.zip (the exact asset name UpdateChecker looks for), commits
  + pushes the version bump, and creates the GitHub Release (tag + asset) via
  the `gh` CLI.
#>

param(
  [switch]$SkipBump
)

$ErrorActionPreference = 'Stop'
$repoRoot = Join-Path $PSScriptRoot '..'

if (-not $SkipBump) {
  & (Join-Path $PSScriptRoot 'bump_build_number.ps1')
}

$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspec = Get-Content -Path $pubspecPath -Raw
$match = [regex]::Match($pubspec, '(?m)^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)')
if (-not $match.Success) {
  throw "Could not find a 'version: X.Y.Z+N' line in $pubspecPath"
}
$tag = "v$($match.Groups[1].Value)+$($match.Groups[2].Value)"

if (-not $SkipBump) {
  git -C $repoRoot add pubspec.yaml
  git -C $repoRoot commit -m "Bump build number for $tag"
  git -C $repoRoot push
}

& "C:\Dev\SDK\Flutter\flutter\bin\flutter.bat" build windows --release

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $releaseDir 'Cardflux.exe'))) {
  throw "Build did not produce Cardflux.exe in $releaseDir"
}

$zipPath = Join-Path $repoRoot 'build\cardflux-windows.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath

& "C:\Program Files\GitHub CLI\gh.exe" release create $tag $zipPath --repo jvthompson/cardflux --title $tag --generate-notes

Write-Host "Published $tag"
