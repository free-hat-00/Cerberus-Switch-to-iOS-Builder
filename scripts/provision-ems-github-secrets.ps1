#Requires -RunAsAdministrator
# Run LOCALLY on EMS from an elevated PowerShell console.
# Sets exactly three GitHub Actions encrypted repository secrets.
# Never displays or uploads secret material to this public repository.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo='free-hat-00/Cerberus-Switch-to-iOS-Builder'
$secure='C:\ProgramData\NxNativeBuilder'
$key=Join-Path $secure 'client_ed25519'
$hostKey='C:\ProgramData\ssh\ssh_host_ed25519_key.pub'
$account='nxnative-ci'
if(!(Test-Path -LiteralPath $key -PathType Leaf)){throw 'EMS private key missing'}
if(!(Test-Path -LiteralPath $hostKey -PathType Leaf)){throw 'SSH host public key missing'}
if(!(Get-Command gh -ErrorAction SilentlyContinue)){throw 'GitHub CLI not found'}
$login=(& gh api user --jq .login 2>$null)
if($LASTEXITCODE -ne 0 -or $login.Trim() -ne 'free-hat-00'){
  throw 'GitHub CLI is not authenticated as free-hat-00 in this elevated PowerShell session. Run gh auth login here first.'
}
$hostParts=(Get-Content -LiteralPath $hostKey -Raw).Trim() -split '\s+'
if($hostParts.Length -lt 2 -or $hostParts[0] -ne 'ssh-ed25519'){throw 'Unexpected SSH host public key type'}
$known='ems.corvus-gamut.ts.net '+$hostParts[0]+' '+$hostParts[1]
# Only encrypted GitHub Actions secret API is used, never shell argument -b.
# The key stays in the privileged file; its content is piped to gh stdin.
Get-Content -LiteralPath $key -Raw | & gh secret set EMS_SSH_PRIVATE_KEY -R $repo
if($LASTEXITCODE -ne 0){throw 'Failed to upload EMS_SSH_PRIVATE_KEY'}
$known | & gh secret set EMS_SSH_KNOWN_HOSTS -R $repo
if($LASTEXITCODE -ne 0){throw 'Failed to upload EMS_SSH_KNOWN_HOSTS'}
$account | & gh secret set EMS_SSH_USER -R $repo
if($LASTEXITCODE -ne 0){throw 'Failed to upload EMS_SSH_USER'}
Write-Output 'DONE: 3 EMS SSH secrets provisioned, without displaying private key.'
Write-Output 'Build gate remains disabled. Next: test tagged Tailscale runner against EMS port 22 and denied endpoints.'
