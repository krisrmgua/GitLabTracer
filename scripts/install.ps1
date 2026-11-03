# Builds and installs Pipeline Tracer on Windows. Run from a normal (non-admin) PowerShell.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw "npm is required. Install Node.js 20+ LTS first (winget install OpenJS.NodeJS.LTS)."
}

foreach ($tool in @(@{ Name = "glab"; Id = "glab.glab" }, @{ Name = "gh"; Id = "GitHub.cli" })) {
  if (-not (Get-Command $tool.Name -ErrorAction SilentlyContinue)) {
    Write-Warning "$($tool.Name) not found on PATH. Install it with: winget install --id $($tool.Id)"
  }
}

# Stop a running copy so the installer can replace its files.
Get-Process -Name "Pipeline Tracer" -ErrorAction SilentlyContinue | Stop-Process -Force

npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
npm run pack:win
if ($LASTEXITCODE -ne 0) { throw "npm run pack:win failed" }

$Setup = Get-ChildItem -Path (Join-Path $Root "release") -Filter "Pipeline Tracer Setup*.exe" -Recurse |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $Setup) {
  throw "Installer not found under release\"
}

Write-Host "Launching $($Setup.FullName)"
Start-Process -FilePath $Setup.FullName -Wait
Write-Host "Pipeline Tracer installed. Look for the ring icon in the system tray (check the ^ overflow)."
