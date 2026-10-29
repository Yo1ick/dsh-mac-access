param(
  [string]$ToolsDir = $PSScriptRoot,
  [string]$LnkName = 'Mac DSH.lnk'
)
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path $desktop $LnkName))
$lnk.TargetPath = Join-Path $ToolsDir 'open-mac-dsh.cmd'
$lnk.WorkingDirectory = $ToolsDir
$lnk.WindowStyle = 7
$lnk.Description = 'Open Mac DSH with fresh token'
$lnk.Save()
Write-Output "desktop=$desktop"
Write-Output "exists=$(Test-Path (Join-Path $desktop $LnkName))"
