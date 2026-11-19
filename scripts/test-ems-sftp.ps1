#Requires -RunAsAdministrator
# Verify EMS SFTP-only identity with harmless dummy files.
# Never reads, uploads, or prints real Switch files or encryption keys.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$base='C:\NxNativeSFTP'
$secure='C:\ProgramData\NxNativeBuilder'
$private=Join-Path $secure 'client_ed25519'
$hostPublic='C:\ProgramData\ssh\ssh_host_ed25519_key.pub'
$sshdCfg='C:\ProgramData\ssh\sshd_config'
$sftp='C:\Windows\System32\OpenSSH\sftp.exe'
$sshd='C:\Windows\System32\OpenSSH\sshd.exe'

foreach($p in @($private,$hostPublic,$sshdCfg,$sftp,"$base\in","$base\out")){
  if(!(Test-Path -LiteralPath $p -PathType Any)){throw "Missing test prerequisite: $p"}
}
& $sshd -t -f $sshdCfg
if($LASTEXITCODE -ne 0){throw 'sshd syntax / hostkey validation failed'}
if((Get-Service sshd).Status -ne 'Running'){throw 'sshd service is not running'}
$testName='test-'+[guid]::NewGuid().ToString('N')
$temp=Join-Path $env:TEMP $testName
New-Item -ItemType Directory -Path $temp -ErrorAction Stop | Out-Null
try{
  $marker=Join-Path $temp 'probe.txt'
  Set-Content -LiteralPath $marker -Value $testName -NoNewline -Encoding ascii
  $remote=Join-Path "$base\in" "$testName.txt"
  Copy-Item -LiteralPath $marker -Destination $remote -ErrorAction Stop

  $parts=(Get-Content -LiteralPath $hostPublic -Raw).Trim() -split '\s+'
  if($parts.Length -lt 2 -or $parts[0] -ne 'ssh-ed25519'){throw 'Unexpected SSH host public key'}
  $known=Join-Path $temp 'known_hosts'
  Set-Content -LiteralPath $known -Value ('localhost '+$parts[0]+' '+$parts[1]) -Encoding ascii

  $batchGood=Join-Path $temp 'test-good.sftp'
  $download=Join-Path $temp 'download.txt'
  $remoteOut="/out/$testName.txt"
  # The in-jail /in path is read-only, /out is writable.
  Set-Content -LiteralPath $batchGood -Value @(
    'pwd',
    'ls /in',
    "get /in/$testName.txt `"$download`"",
    "put `"$marker`" $remoteOut"
  ) -Encoding ascii

  $opts=@('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
          '-o',('UserKnownHostsFile='+$known),'-o','IdentitiesOnly=yes',
          '-o','HostKeyAlgorithms=ssh-ed25519','-i',$private)
  & $sftp @opts -b $batchGood 'nxnative-ci@localhost'
  if($LASTEXITCODE -ne 0){throw 'Positive SFTP test failed'}
  if((Get-Content -LiteralPath $download -Raw) -ne $testName){throw 'SFTP readback contents differ'}
  if(!(Test-Path -LiteralPath "$base\out\$testName.txt")){throw 'SFTP output upload not found'}

  $batchDeny=Join-Path $temp 'test-deny.sftp'
  # Attempt to access a location outside the jail. The command MUST fail.
  Set-Content -LiteralPath $batchDeny -Value 'ls /C:/Windows' -Encoding ascii
  & $sftp @opts -b $batchDeny 'nxnative-ci@localhost'
  if($LASTEXITCODE -eq 0){throw 'SECURITY FAILURE: SFTP outside-jail lookup succeeded'}
  Write-Output 'PASS: SFTP authentication, staged read, output write and outside-jail deny.'
}finally{
  Remove-Item -LiteralPath "$base\in\$testName.txt","$base\out\$testName.txt" -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
}
