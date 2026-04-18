# IEM Mixer — Windows one-shot installer
# Usage:
#   irm https://raw.githubusercontent.com/cgamache/iem-mixer-releases/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/cgamache/iem-mixer-releases/main/install.ps1))) -X32Ip 192.168.1.100

param(
    [string]$X32Ip = "",
    [switch]$NoService,
    [switch]$DryRun
)

# ─── Configuration ────────────────────────────────────────────────────────────
$GhRepo      = "cgamache/iem-mixer-releases"
$InstallDir  = "C:\Program Files\iem-mixer"
$ServiceName = "iem-mixer"

# ─── Platform detection ───────────────────────────────────────────────────────
$Arch = $env:PROCESSOR_ARCHITECTURE
if ($Arch -ne "AMD64") {
    Write-Error "Unsupported architecture: $Arch (only win-x64 supported)"
    exit 1
}
$Rid = "win-x64"
Write-Host "Platform: Windows $Arch -> $Rid"

# ─── Dry-run mode (before any network calls) ─────────────────────────────────
if ($DryRun) {
    Write-Host ""
    Write-Host "[dry-run] Would fetch latest version from: https://api.github.com/repos/$GhRepo/releases/latest"
    Write-Host "[dry-run] Would download: https://github.com/$GhRepo/releases/download/v<version>/iem-mixer-<version>-$Rid.zip"
    Write-Host "[dry-run] Would install to: $InstallDir"
    Write-Host "[dry-run] Would write appsettings.json with X32 IP: $(if ($X32Ip) { $X32Ip } else { '<prompt>' })"
    Write-Host "[dry-run] Install service: $(-not $NoService)"
    exit 0
}

# ─── Resolve latest version from GitHub API ──────────────────────────────────
$Release = Invoke-RestMethod "https://api.github.com/repos/$GhRepo/releases/latest"
$Version  = $Release.tag_name.TrimStart('v')
if (-not $Version) {
    Write-Error "Could not determine latest version from GitHub."
    exit 1
}
Write-Host "Version:  $Version"

$Archive     = "iem-mixer-$Version-$Rid.zip"
$DownloadUrl = "https://github.com/$GhRepo/releases/download/v$Version/$Archive"

# ─── Prompt for X32 IP if not supplied ───────────────────────────────────────
if (-not $X32Ip) {
    $X32Ip = Read-Host "Enter X32 IP address"
}
if (-not $X32Ip) {
    Write-Error "X32 IP address is required."
    exit 1
}

# ─── Download + extract ──────────────────────────────────────────────────────
$Tmp = Join-Path $env:TEMP "iem-mixer-install-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    Write-Host "Downloading $Archive..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile "$Tmp\$Archive" -UseBasicParsing

    Write-Host "Installing to $InstallDir..."
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    Expand-Archive -Path "$Tmp\$Archive" -DestinationPath "$Tmp\extracted"

    # Archive contains a top-level directory named after the RID
    $ExtractedDir = Join-Path $Tmp "extracted\$Rid"
    if (-not (Test-Path $ExtractedDir)) {
        Write-Error "Unexpected archive structure: expected subdirectory '$Rid' not found."
        exit 1
    }
    Move-Item $ExtractedDir $InstallDir
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

# ─── Verify binary exists ─────────────────────────────────────────────────────
$ExePath = Join-Path $InstallDir "iem-mixer-dotnet.exe"
if (-not (Test-Path $ExePath)) {
    Write-Error "Binary not found after extraction: $ExePath"
    exit 1
}

# ─── Write appsettings.json ──────────────────────────────────────────────────
$AppSettings = @"
{
  "X32": {
    "IpAddress": "$X32Ip",
    "Port": 10023
  },
  "Kestrel": {
    "Endpoints": {
      "Http": { "Url": "http://0.0.0.0:5000" }
    }
  }
}
"@
Set-Content -Path "$InstallDir\appsettings.json" -Value $AppSettings -Encoding UTF8
Write-Host "Config written: X32 at ${X32Ip}:10023, listening on :5000"

# ─── Service install ──────────────────────────────────────────────────────────
if (-not $NoService) {
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Stop-Service $ServiceName -Force
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
    New-Service -Name $ServiceName `
                -DisplayName "IEM Mixer" `
                -BinaryPathName "`"$ExePath`"" `
                -StartupType Automatic `
                -Description "IEM Mixer X32 monitor mix controller"
    Start-Service $ServiceName
    Write-Host "Windows Service '$ServiceName' installed and started."
}

# ─── Detect LAN IP for final message ─────────────────────────────────────────
$LanIp = (Get-NetIPAddress -AddressFamily IPv4 |
          Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } |
          Sort-Object -Property PrefixLength |
          Select-Object -First 1).IPAddress

if (-not $LanIp) { $LanIp = "<this-machine-ip>" }

Write-Host ""
Write-Host "IEM Mixer installed successfully."
Write-Host "Connect phones to: http://${LanIp}:5000/monitor/1"
