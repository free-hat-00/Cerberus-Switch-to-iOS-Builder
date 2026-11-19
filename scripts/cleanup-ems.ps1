# Run on EMS to remove temporary staged game package and copied prod.keys.
# Does not remove build output.
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern('^[A-Za-z0-9_-]{12,40}$')]
  [string]$BuildId
)
$ErrorActionPreference = 'Stop'
$root = 'D:\Emulators\Switch\.nxnative-staging'
$target = Join-Path $root $BuildId
if (!(Test-Path -LiteralPath $target -PathType Container)) {
  Write-Output 'No staging directory found.'
  exit 0
}
if ($PSCmdlet.ShouldProcess($target,'Delete staging files and copied keys')) {
  Remove-Item -LiteralPath $target -Recurse -Force
  Write-Output 'Staging directory removed. IPA output, if any, remains in C:\\NxNativeSFTP\\out.'
}
