#Requires -RunAsAdministrator
# One-time EMS SFTP-only account setup. Run from elevated Windows PowerShell.
# Backups sshd_config, verifies config before restart, never prints key material.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$user = 'nxnative-ci'
$root = 'C:\NxNativeSFTP'
$config = 'C:\ProgramData\ssh\sshd_config'
$secure = 'C:\ProgramData\NxNativeBuilder'
$operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($operator -notmatch '^[^\\]+\\[^\\]+$') { throw 'Cannot identify local operator.' }
if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
  throw 'nxnative-ci already exists. Refusing to overwrite or rotate an existing identity.'
}
if (Test-Path -LiteralPath $root) { throw 'C:\NxNativeSFTP already exists. Review manually; refusing overwrite.' }
if (Test-Path -LiteralPath $secure) { throw 'C:\ProgramData\NxNativeBuilder already exists. Review manually.' }
if (!(Test-Path -LiteralPath $config)) { throw 'Windows sshd_config missing.' }
$original = Get-Content -LiteralPath $config -Raw
if ($original -notmatch '(?m)^AllowUsers\s+cerberus\s*$') {
  throw 'Expected existing AllowUsers cerberus restriction not found; refusing config change.'
}
if ($original -match '(?m)^Match\s') { throw 'Existing Match block detected; review manually.' }
$backup = "$config.nxnative-backup-$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -LiteralPath $config -Destination $backup

# Random local account password is never displayed, stored or placed on GitHub.
$alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%+=_-'
$bytes = New-Object byte[] 64
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$passwordText = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
$password = ConvertTo-SecureString $passwordText -AsPlainText -Force
$passwordText = $null
New-LocalUser -Name $user -Password $password -FullName 'NxNative restricted SFTP account' -Description 'SFTP-only GitHub builder - no administrator rights' -PasswordNeverExpires | Out-Null
# Local accounts are non-admin unless explicitly added to Administrators.
if (Get-LocalGroupMember -Group Administrators | Where-Object { $_.Name -match '(?i)\\nxnative-ci$' }) {
  throw 'Refusing to continue: builder account unexpectedly administrator.'
}

New-Item -ItemType Directory -Path $root,"$root\in","$root\out",$secure -Force | Out-Null
function Set-AclExact($path, [string[]]$grants) {
  & icacls.exe $path '/inheritance:r' | Out-Null
  $args = @($path,'/grant:r') + $grants
  & icacls.exe @args | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ACL setup failed for $path" }
}
$admins = 'BUILTIN\Administrators:(OI)(CI)F'
$system = 'NT AUTHORITY\SYSTEM:(OI)(CI)F'
$reader = "nxnative-ci:(OI)(CI)RX"
$operatorMod = "${operator}:(OI)(CI)M"
Set-AclExact $root @($admins,$system,$reader)
Set-AclExact "$root\in" @($admins,$system,$reader,$operatorMod)
Set-AclExact "$root\out" @($admins,$system,"nxnative-ci:(OI)(CI)M",$operatorMod)
Set-AclExact $secure @($admins,$system)

$private = "$secure\client_ed25519"
& ssh-keygen.exe -q -t ed25519 -N '' -f $private
if ($LASTEXITCODE -ne 0 -or !(Test-Path "$private.pub")) { throw 'SSH key generation failed.' }
Copy-Item -LiteralPath "$private.pub" -Destination "$secure\authorized_keys" -Force
$grantAdmin = @('BUILTIN\Administrators:F','NT AUTHORITY\SYSTEM:F')
foreach ($file in @($private,"$private.pub","$secure\authorized_keys")) {
  & icacls.exe $file '/inheritance:r' '/grant:r' @grantAdmin | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to protect SSH file $file" }
}
# Public host key fingerprint can be displayed; no private keys.
$hostkey = 'C:\ProgramData\ssh\ssh_host_ed25519_key.pub'
if (Test-Path $hostkey) { & ssh-keygen.exe -lf $hostkey }

$updated = $original -replace '(?m)^AllowUsers\s+cerberus\s*$', 'AllowUsers cerberus nxnative-ci'
$updated += @'

# NxNative builder: dedicated SFTP-only chroot. Existing cerberus login unchanged.
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
  Set-Content -LiteralPath $config -Value $updated -Encoding ascii
  & 'C:\Windows\System32\OpenSSH\sshd.exe' -t -f $config
  if ($LASTEXITCODE -ne 0) { throw 'OpenSSH syntax validation failed.' }
  Restart-Service sshd -ErrorAction Stop
  Write-Output 'SETUP COMPLETE: Account created, SFTP chroot configured, OpenSSH restarted.'
  Write-Output 'DO NOT enable GitHub builds yet. Test the new account and deny access to paths outside jail.'
  Write-Output "GitHub SSH private secret source (local only): $private"
  Write-Output "SSH known_hosts host key source: $hostkey"
  Write-Output "Backup sshd_config: $backup"
} catch {
  Copy-Item -LiteralPath $backup -Destination $config -Force
  try { Restart-Service sshd -ErrorAction Stop } catch { Write-Warning 'SSH restart failed. Check service manually.' }
  throw
}
