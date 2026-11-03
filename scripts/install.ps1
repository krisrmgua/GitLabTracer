# Install Pipeline Tracer on Windows (run from a normal PowerShell)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw "npm is required. Install Node.js 20 LTS or newer first."
}
$NodeMajor = [int]((node -p "process.versions.node.split('.')[0]").Trim())
if ($NodeMajor -lt 20) {
  throw "Node.js 20 or newer is required (found $(node -v))."
}
if (-not (Get-Command glab -ErrorAction SilentlyContinue) -and -not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Warning "Neither glab nor gh is on PATH. Install one (winget install GLab.GLab or winget install GitHub.cli) and sign in, or the panel stays empty."
}

npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
npm run pack:win
if ($LASTEXITCODE -ne 0) { throw "npm run pack:win failed" }

$Setup = Get-ChildItem -Path (Join-Path $Root "release") -Filter "Pipeline Tracer Setup*.exe" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $Setup) {
  throw "Installer not found under release\"
}

Get-Process -Name "Pipeline Tracer" -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Launching $($Setup.FullName)"
Start-Process -FilePath $Setup.FullName -Wait
Write-Host "Pipeline Tracer installer finished. The tray icon appears after launch (check the ^ overflow)."
