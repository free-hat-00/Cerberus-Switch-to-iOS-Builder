#Requires -RunAsAdministrator
# Recover the partially-completed EMS setup after Windows PowerShell 5.1
# swallowed ssh-keygen's empty passphrase argument.
# Run ONLY after inspecting this script and confirming the account was created.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$user = 'nxnative-ci'
$operator = "$env:COMPUTERNAME\cerberus"
$root = 'C:\NxNativeSFTP'
$secure = 'C:\ProgramData\NxNativeBuilder'
$config = 'C:\ProgramData\ssh\sshd_config'
$private = Join-Path $secure 'client_ed25519'
$public = "$private.pub"
$authorized = Join-Path $secure 'authorized_keys'
$sshd = 'C:\Windows\System32\OpenSSH\sshd.exe'
$sshgen = 'C:\Windows\System32\OpenSSH\ssh-keygen.exe'

if (!(Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) { throw 'Expected nxnative-ci account not found. No changes made.' }
if (Get-LocalGroupMember -Group Administrators | Where-Object { $_.Name -match '(?i)\\nxnative-ci$' }) { throw 'Builder account is an administrator. Stop.' }
foreach ($path in @($root, "$root\in", "$root\out", $secure, $config)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing prerequisite: $path" }
}
if (!(Get-LocalUser -Name cerberus -ErrorAction SilentlyContinue)) { throw 'Existing operator account missing.' }
# Fix root traversal so the normal operator can stage files to the jail.
& icacls.exe $root '/grant:r' ("${operator}:(RX)") | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to grant operator read/traverse access to jail root.' }

if ((Test-Path -LiteralPath $private) -xor (Test-Path -LiteralPath $public)) {
  throw 'Incomplete SSH keypair already exists. Refusing overwrite; inspect manually.'
}
if (!(Test-Path -LiteralPath $private)) {
  # Windows PowerShell 5.1 does NOT preserve empty native-process arguments.
  # cmd.exe passes -N "" intact. Tested on EMS with disposable keypair.
  $line = ('"' + $sshgen + '" -q -t ed25519 -N "" -f "' + $private + '"')
  & cmd.exe /d /s /c $line
  if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $private) -or !(Test-Path -LiteralPath $public)) {
    throw 'SSH key generation failed. No sshd_config changes attempted.'
  }
}
if (!(Test-Path -LiteralPath $authorized)) {
  Copy-Item -LiteralPath $public -Destination $authorized -ErrorAction Stop
}
foreach ($file in @($private,$public,$authorized)) {
  & icacls.exe $file '/inheritance:r' '/grant:r' 'BUILTIN\Administrators:F' 'NT AUTHORITY\SYSTEM:F' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Unable to protect SSH file $file" }
}

$original = Get-Content -LiteralPath $config -Raw
if ($original -match '(?m)^Match\s+User\s+nxnative-ci\b') {
  Write-Output 'Existing nxnative-ci sshd Match block detected. No duplicate configuration written.'
} else {
  if ($original -notmatch '(?m)^AllowUsers\s+cerberus\s*$') {
    throw 'Unexpected sshd AllowUsers configuration. Refusing automatic modification.'
  }
  if ($original -match '(?m)^Match\s') { throw 'Other SSH Match blocks present. Review config before editing.' }
  $backup = "$config.nxnative-recovery-$(Get-Date -Format yyyyMMddHHmmss)"
  Copy-Item -LiteralPath $config -Destination $backup -ErrorAction Stop
  $updated = $original -replace '(?m)^AllowUsers\s+cerberus\s*$', 'AllowUsers cerberus nxnative-ci'
  $updated += @'

# Restricted SFTP-only nxnative CI identity.
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
  try {
    Set-Content -LiteralPath $config -Value $updated -Encoding ascii -ErrorAction Stop
    & $sshd -t -f $config
    if ($LASTEXITCODE -ne 0) { throw 'SSH configuration syntax check failed.' }
    Restart-Service sshd -ErrorAction Stop
  } catch {
    Copy-Item -LiteralPath $backup -Destination $config -Force
    try { Restart-Service sshd -ErrorAction Stop } catch { Write-Warning 'Restore sshd service manually.' }
    throw
  }
  Write-Output "SSH config backup: $backup"
}
Write-Output 'Recovery script completed. DO NOT configure GitHub secrets or enable builds yet.'
Write-Output 'Next: verify SFTP chroot, SSH authentication and denied traversal outside the jail.'
Write-Output 'Private key remains local in C:\ProgramData\NxNativeBuilder\client_ed25519; do not paste it into chat.'
