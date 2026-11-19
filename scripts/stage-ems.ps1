# Run locally on EMS. Stages ONE game directory and prod.keys for a private build.
# Example:
#   .\stage-ems.ps1 -GameFolder 'Super Mario Bros. Wonder'
# Output is an opaque build ID, not the game name.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$GameFolder
)
$ErrorActionPreference = 'Stop'
$root = 'D:\Emulators\Switch'
$games = Join-Path $root 'Games - ROMs'
$key = Join-Path $root 'Ryujinx\publish\Keys-22.1.0\prod.keys'
$stageRoot = Join-Path $root '.nxnative-staging'
$outputRoot = Join-Path $root '.nxnative-outputs'

if (!(Test-Path -LiteralPath $key -PathType Leaf)) { throw 'prod.keys was not found.' }
if (!(Test-Path -LiteralPath $games -PathType Container)) { throw 'Game root not found.' }
# Exact immediate child folder match prevents traversal.
$matches = @(Get-ChildItem -LiteralPath $games -Directory | Where-Object { $_.Name -ceq $GameFolder })
if ($matches.Count -ne 1) { throw 'Select an existing game directory by its exact name.' }
$game = $matches[0].FullName
$hasPackage = @(Get-ChildItem -LiteralPath $game -File -Recurse | Where-Object { $_.Extension -in @('.nsp','.xci','.nsz','.xcz') }).Count -gt 0
if (!$hasPackage) { throw 'No NSP/XCI/NSZ/XCZ package found inside this directory.' }

$id = ([guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageRoot $id
$out = Join-Path $outputRoot $id
New-Item -ItemType Directory -Force -Path $stage,$out | Out-Null
try {
  Copy-Item -LiteralPath $key -Destination (Join-Path $stage 'prod.keys') -ErrorAction Stop
  # Archive the selected folder contents; no names or contents are sent to GitHub.
  & tar.exe -cf (Join-Path $stage 'game.tar') -C $game .
  if ($LASTEXITCODE -ne 0) { throw 'tar failed to stage the selected directory.' }
  Write-Output "BUILD_ID=$id"
  Write-Output 'Run GitHub Actions > NxNative private EMS builder with this build ID.'
  Write-Output 'After the run, delete the staging folder and keys using cleanup-ems.ps1.'
} catch {
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  throw
}
