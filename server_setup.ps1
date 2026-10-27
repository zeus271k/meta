# ==============================================================================
# server_setup.ps1 - Central Repository Initialization & Manifest Generator
# Run with Administrator privileges on the Central Server PC
# ==============================================================================

[CmdletBinding()]
param (
    [string]$RepoPath = "$PSScriptRoot",
    [string]$ShareName = "LLM_Deploy",
    [int]$HttpPort = 8080
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Central Repository Setup & Manifest Generation        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Verify Directory Structure
$BootFolderName = if (Test-Path (Join-Path $RepoPath "boot")) { "boot" } else { ".sys_cache" }
$RequiredDirs = @("bin", "py", "data")
foreach ($dir in $RequiredDirs) {
    $fullPath = Join-Path -Path $RepoPath -ChildPath "$BootFolderName\$dir"
    if (-not (Test-Path $fullPath)) {
        Write-Warning "Directory not found: $fullPath. Creating placeholder..."
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
}

# 2. Configure Windows SMB 3.0 Share
Write-Host "`n[+] Configuring Windows SMB Share: \\$env:COMPUTERNAME\$ShareName..." -ForegroundColor Green

# Ensure Server service is running
Set-Service -Name LanmanServer -StartupType Automatic
Start-Service -Name LanmanServer

# Remove existing share if present
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Write-Host "    Removing existing share..." -ForegroundColor Yellow
    Remove-SmbShare -Name $ShareName -Force
}

# Create New SMB Share with Read-Only Access for Everyone
$SourceDir = (Resolve-Path $RepoPath).Path
New-SmbShare -Name $ShareName -Path $SourceDir -ReadAccess "Everyone" -Description "Central Offline LLM Distribution Share" | Out-Null

# Allow File and Printer Sharing through Windows Defender Firewall
Write-Host "[+] Configuring Windows Firewall for File Sharing..." -ForegroundColor Green
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue

# 3. Generate Cryptographic manifest.json
Write-Host "`n[+] Generating SHA-256 Manifest for Models and Runtimes..." -ForegroundColor Green

$Manifest = [ordered]@{
    version        = "1.2.0"
    generated_at   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    server_host    = $env:COMPUTERNAME
    share_name     = $ShareName
    models         = @()
    runtimes       = @()
}

# Hash Model Binaries
$DataDir = Join-Path -Path $RepoPath -ChildPath "$BootFolderName\data"
if (Test-Path $DataDir) {
    Get-ChildItem -Path $DataDir -File | ForEach-Object {
        Write-Host "    Hashing model: $($_.Name) ($([Math]::Round($_.Length / 1MB, 2)) MB)..." -ForegroundColor Gray
        $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $Manifest.models += [ordered]@{
            filename  = $_.Name
            rel_path  = "$BootFolderName\data\$($_.Name)"
            size_bytes = $_.Length
            sha256    = $hash
            min_ram_gb = if ($_.Name -like "*symbols*") { 14 } else { 8 }
        }
    }
}

# Hash Critical Binaries
$BinDir = Join-Path -Path $RepoPath -ChildPath "$BootFolderName\bin"
if (Test-Path $BinDir) {
    Get-ChildItem -Path $BinDir -File -Filter "*.exe" | ForEach-Object {
        $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $Manifest.runtimes += [ordered]@{
            filename   = $_.Name
            rel_path   = "$BootFolderName\bin\$($_.Name)"
            size_bytes = $_.Length
            sha256     = $hash
        }
    }
}

$ManifestJsonPath = Join-Path -Path $RepoPath -ChildPath "manifest.json"
$Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $ManifestJsonPath -Encoding UTF8
Write-Host "[+] Manifest generated successfully at: $ManifestJsonPath" -ForegroundColor Green

# 4. Create Incoming Telemetry Logs Directory
$LogsDir = Join-Path -Path $RepoPath -ChildPath "logs"
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}
# Grant Full Control to Everyone for the logs folder only (so clients can post status)
icacls $LogsDir /grant "Everyone:(OI)(CI)M" /T /Q | Out-Null

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "   Central Server is Ready!                              " -ForegroundColor Cyan
Write-Host "   SMB Path: \\$env:COMPUTERNAME\$ShareName               " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
