# open-mac-dsh.ps1 - Open the Mac DSH GUI from Windows.
# The Mac side pushes its current login URL to $env:MAC_DSH_URL_FILE (or ~/.dsh/mac-dsh-url.txt).
# -Tunnel : rewrite to 127.0.0.1:<TunnelPort> through an SSH tunnel (needs Windows->Mac SSH working)
# -NoOpen : print the URL only (for headless checks), token redacted
# Mac address: set $env:MAC_DSH_MAC_USER / $env:MAC_DSH_MAC_HOST, or pass -MacUser / -MacHost.
param(
  [switch]$Tunnel,
  [switch]$NoOpen,
  [int]$TunnelPort = 13080,
  [string]$MacUser = $env:MAC_DSH_MAC_USER,
  [string]$MacHost = $env:MAC_DSH_MAC_HOST,
  [string]$UrlFile = $(if ($env:MAC_DSH_URL_FILE) { $env:MAC_DSH_URL_FILE } else { Join-Path $env:USERPROFILE '.dsh\mac-dsh-url.txt' })
)

$ErrorActionPreference = 'Stop'
$file = $UrlFile

if (-not (Test-Path $file)) {
  Write-Error "No $file - wait for the Mac push (runs every 60s) or check the push LaunchAgent."
  exit 1
}
$url = ((Get-Content $file -Raw) -replace '\s+$', '').Trim()
if ($url -notmatch '^http://[^/]+:\d+/\?token=') {
  Write-Error "Bad URL in $file : '$url'"
  exit 1
}

if ($Tunnel) {
  if (-not $MacUser -or -not $MacHost) {
    Write-Error 'Tunnel mode needs -MacUser/-MacHost (or MAC_DSH_MAC_USER / MAC_DSH_MAC_HOST).'
    exit 2
  }
  # Ensure the SSH tunnel is up (any 3-digit HTTP code means the tunnel answers).
  $alive = (& curl.exe -s -o NUL -w '%{http_code}' -m 5 "http://127.0.0.1:${TunnelPort}/" 2>$null)
  if (-not ($alive -match '^\d{3}$' -and $alive -ne '000')) {
    Start-Process ssh -ArgumentList '-N','-L',"${TunnelPort}:127.0.0.1:3080",'-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=30',"${MacUser}@${MacHost}" -WindowStyle Hidden
    Start-Sleep -Seconds 3
  }
  $target = $url -replace '^http://[^/]+:\d+', "http://127.0.0.1:${TunnelPort}"
} else {
  $target = $url
}

if ($NoOpen) {
  $redacted = $target -replace 'token=[^&]+', 'token=<redacted>'
  Write-Output "OK url=$redacted"
} else {
  Write-Output "Opening: $target"
  Start-Process $target
}
