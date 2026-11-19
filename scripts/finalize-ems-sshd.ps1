#Requires -RunAsAdministrator
# Finish partially completed EMS nxnative SFTP setup after sshd-dependent-service failure.
# Only changes sshd_config and restarts sshd; never changes existing keys or accounts.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$cfg='C:\ProgramData\ssh\sshd_config'
$sshd='C:\Windows\System32\OpenSSH\sshd.exe'
$account='nxnative-ci'
$keyDir='C:\ProgramData\NxNativeBuilder'
foreach($path in @('C:\NxNativeSFTP\in','C:\NxNativeSFTP\out',"$keyDir\client_ed25519","$keyDir\client_ed25519.pub","$keyDir\authorized_keys",$cfg)){
  if(!(Test-Path -LiteralPath $path)){throw "Missing required setup component: $path"}
}
if(!(Get-LocalUser -Name $account -ErrorAction SilentlyContinue)){throw 'Restricted account missing'}
if(Get-LocalGroupMember -Group Administrators | Where-Object {$_.Name -match '(?i)\\nxnative-ci$'}){throw 'Account is privileged; aborting'}
$before=Get-Content -LiteralPath $cfg -Raw
if($before -match '(?m)^Match\s'){throw 'An SSH Match block already exists; inspect before applying'}
if($before -notmatch '(?m)^AllowUsers\s+cerberus\s*$'){throw 'Unexpected AllowUsers policy; refusing overwrite'}
$backup="$cfg.nxnative-finalize-$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -LiteralPath $cfg -Destination $backup
$after=$before -replace '(?m)^AllowUsers\s+cerberus\s*$','AllowUsers cerberus nxnative-ci'
$after+=@'

# Dedicated non-admin SFTP-only builder; existing cerberus access preserved
Match User nxnative-ci
    PasswordAuthentication no
    PubkeyAuthentication yes
    AuthorizedKeysFile __PROGRAMDATA__/NxNativeBuilder/authorized_keys
    ChrootDirectory C:/NxNativeSFTP
    ForceCommand internal-sftp
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
'@
try{
  Set-Content -LiteralPath $cfg -Value $after -Encoding ascii
  & $sshd -t -f $cfg
  if($LASTEXITCODE -ne 0){throw 'SSH syntax check failed'}
  # Dependency SshdBroker on this EMS requires Force for service restart.
  # Run LOCALLY in Administrator PowerShell (not over SSH).
  Restart-Service -Name sshd -Force -ErrorAction Stop
  if((Get-Service sshd).Status -ne 'Running'){throw 'sshd is not running'}
  Write-Output 'SSH CONFIG APPLIED; service running. Next step: SFTP positive/negative access tests.'
  Write-Output "Config backup: $backup"
}catch{
  Write-Warning 'Applying or restarting SSH failed. Restoring previous configuration.'
  Copy-Item -LiteralPath $backup -Destination $cfg -Force
  try{Restart-Service -Name sshd -Force -ErrorAction Stop}catch{Write-Warning 'Service restart failed after rollback. Inspect manually.'}
  throw
}
