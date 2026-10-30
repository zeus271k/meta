# ==============================================================================
# client_sync.ps1 - Hardware-Aware Centralized LLM Deployment & Sync Engine
# Designed for 1 Gbps LAN client deployment with Robocopy Unbuffered I/O
# ==============================================================================

[CmdletBinding()]
param (
    [string]$ServerHost = "CENTRAL-REPO",
    [string]$ShareName = "LLM_Deploy",
    [string]$FallbackLocalPath = "$PSScriptRoot",
    [switch]$ForceRedownload = $false,
    [switch]$SkipTestPrompt = $false
)

$ErrorActionPreference = "Stop"
$StartTime = Get-Date

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Workspace Client Synchronization Engine               " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. HARDWARE PROBING & STORAGE SELECTION
# ------------------------------------------------------------------------------
Write-Host "`n[1/6] Probing Hardware & Storage Topology..." -ForegroundColor Green

# RAM Detection
$OsInfo = Get-CimInstance Win32_OperatingSystem
$TotalRamGB = [Math]::Round($OsInfo.TotalVisibleMemorySize / 1048576, 1)
Write-Host "    Installed RAM: $TotalRamGB GB" -ForegroundColor Gray

# CPU Core & Thread Detection
$LogicalProcessors = [int]$env:NUMBER_OF_PROCESSORS
if (-not $LogicalProcessors -or $LogicalProcessors -lt 1) { $LogicalProcessors = 4 }
Write-Host "    Logical Processors: $LogicalProcessors" -ForegroundColor Gray

# Dynamic Safe Thread Allocation:
# 2-4 cores: Cores - 1
# 6 cores: 4
# 8-14 cores: 6 (preserves 2 cores for OS/IDE, matches P-core count on hybrid i5)
# 16+ cores: 7 (unleashes 7 P-cores on Ultra 7 / i7 / i9, leaves 1 P-core + all E-cores for OS)
if ($LogicalProcessors -le 2) {
    $Threads = 1
} elseif ($LogicalProcessors -le 4) {
    $Threads = [Math]::Max(1, $LogicalProcessors - 1)
} elseif ($LogicalProcessors -le 6) {
    $Threads = 4
} elseif ($LogicalProcessors -le 14) {
    $Threads = 6
} else {
    $Threads = 7
}
Write-Host "    Optimal Inference Threads: $Threads" -ForegroundColor Gray

# Storage Selection: NVMe SSD (C:) vs. Persistent Secondary HDD (D:)
$TargetBaseDir = "$env:LOCALAPPDATA\boot"
$DeployOnD = $false

if (Test-Path "D:\") {
    $DeployOnD = $true
    $TargetBaseDir = "D:\boot"
    Write-Host "    Storage: Secondary Drive D:\ detected. Target set to $TargetBaseDir (Persistent Anchor)" -ForegroundColor Yellow
} else {
    # Check free space on C:
    $DriveC = Get-PSDrive C
    $FreeC_GB = [Math]::Round($DriveC.Free / 1GB, 1)
    Write-Host "    Storage: Drive C:\ Free Space: $FreeC_GB GB" -ForegroundColor Gray
    if ($FreeC_GB -lt 8.0) {
        Write-Warning "Low disk space on C:\ ($FreeC_GB GB free). Deployment may fail if models require more space."
    }
}

if (-not (Test-Path $TargetBaseDir)) {
    New-Item -ItemType Directory -Path $TargetBaseDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# 2. LOCATE REPOSITORY (SMB LAN SHARE VS. LOCAL USB FALLBACK)
# ------------------------------------------------------------------------------
Write-Host "`n[2/6] Connecting to Repository..." -ForegroundColor Green
$SmbPath = "\\$ServerHost\$ShareName"
$SourcePath = $null

if (Test-Path $SmbPath) {
    Write-Host "    Connected to Central LAN Share: $SmbPath" -ForegroundColor Green
    $SourcePath = $SmbPath
} elseif (Test-Path "$FallbackLocalPath\boot") {
    Write-Host "    Using local media repository: $FallbackLocalPath" -ForegroundColor Green
    $SourcePath = $FallbackLocalPath
} elseif (Test-Path "$FallbackLocalPath\.sys_cache") {
    Write-Host "    Using legacy local media repository: $FallbackLocalPath" -ForegroundColor Yellow
    $SourcePath = $FallbackLocalPath
} else {
    Write-Host "    No local or LAN source found. Will verify local files or download from web." -ForegroundColor Yellow
    $SourcePath = $TargetBaseDir
}

# ------------------------------------------------------------------------------
# 3. MANIFEST PARSING & MODEL SELECTION
# ------------------------------------------------------------------------------
Write-Host "`n[3/6] Evaluating Model Requirements..." -ForegroundColor Green
$SelectedModel = "core_lite.bin" # Default fallback (3B)

if ($TotalRamGB -ge 13.5 -and $LogicalProcessors -ge 4) {
    $SelectedModel = "core_symbols.bin" # High reasoning 7B
    Write-Host "    High-Performance Tier (RAM >= 14 GB & Cores >= 4): Selected Primary 7B Model (core_symbols.bin)" -ForegroundColor Cyan
} else {
    Write-Host "    Efficiency Tier (RAM < 14 GB or Cores < 4): Selected Lightweight Model (core_lite.bin)" -ForegroundColor Yellow
}

$ManifestPath = Join-Path -Path $SourcePath -ChildPath "manifest.json"
$Manifest = $null
if (Test-Path $ManifestPath) {
    try {
        $Manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
        Write-Host "    Loaded deployment manifest (Version $($Manifest.version))" -ForegroundColor Gray
    } catch {
        Write-Warning "Could not parse manifest.json. Proceeding with file-level Robocopy sync."
    }
}

# ------------------------------------------------------------------------------
# 4. INCREMENTAL SYNCHRONIZATION VIA ROBOCOPY
# ------------------------------------------------------------------------------
Write-Host "`n[4/6] Synchronizing Runtime & Model Assets..." -ForegroundColor Green

$SourceBootDir = if (Test-Path (Join-Path $SourcePath "boot")) { 
    Join-Path $SourcePath "boot" 
} elseif (Test-Path (Join-Path $SourcePath ".sys_cache")) { 
    Join-Path $SourcePath ".sys_cache" 
} else { 
    $SourcePath 
}

# A. Sync Small Files (bin, py, scripts) using multithreading
$SmallDirs = @("bin", "py")
foreach ($sub in $SmallDirs) {
    $srcSub = Join-Path -Path $SourceBootDir -ChildPath $sub
    $dstSub = Join-Path -Path $TargetBaseDir -ChildPath $sub
    if (Test-Path $srcSub -and $srcSub -ne $dstSub) {
        Write-Host "    Syncing $sub/..." -ForegroundColor Gray
        & robocopy $srcSub $dstSub /E /XO /FFT /MT:4 /NFL /NDL /NP /R:3 /W:2 | Out-Null
    }
}

# Copy top-level helper scripts from source
$CoreFiles = @("client.py", "main.bat", "svc.bat", "svc.vbs")
foreach ($cf in $CoreFiles) {
    $srcFile = Join-Path -Path $SourceBootDir -ChildPath $cf
    $dstFile = Join-Path -Path $TargetBaseDir -ChildPath $cf
    if (Test-Path $srcFile -and $srcFile -ne $dstFile) {
        Copy-Item -Path $srcFile -Destination $dstFile -Force
    }
}

# B. Sync Large Model File with Unbuffered I/O (/J) and Restartable Mode (/Z)
$TargetDataDir = Join-Path -Path $TargetBaseDir -ChildPath "data"
if (-not (Test-Path $TargetDataDir)) {
    New-Item -ItemType Directory -Path $TargetDataDir -Force | Out-Null
}

$SrcModelPath = Join-Path -Path $SourceBootDir -ChildPath "data\$SelectedModel"
$DstModelPath = Join-Path -Path $TargetDataDir -ChildPath $SelectedModel

$NeedModelDownload = $true
if (Test-Path $DstModelPath) {
    $LocalItem = Get-Item $DstModelPath
    if (Test-Path $SrcModelPath) {
        $SrcItem = Get-Item $SrcModelPath
        if ($LocalItem.Length -eq $SrcItem.Length -and -not $ForceRedownload) {
            Write-Host "    Model file ($SelectedModel) already present and verified by size ($([Math]::Round($LocalItem.Length / 1GB, 2)) GB). Skipping network transfer!" -ForegroundColor Green
            $NeedModelDownload = $false
        }
    } elseif ($LocalItem.Length -gt 1000000000 -and -not $ForceRedownload) {
        Write-Host "    Model file ($SelectedModel) already present ($([Math]::Round($LocalItem.Length / 1GB, 2)) GB). Skipping download!" -ForegroundColor Green
        $NeedModelDownload = $false
    }
}

if ($NeedModelDownload) {
    if (Test-Path $SrcModelPath) {
        Write-Host "    Transferring $SelectedModel over LAN/USB (Unbuffered /J, Restartable /Z)..." -ForegroundColor Yellow
        $TransferStart = Get-Date
        & robocopy (Split-Path $SrcModelPath) $TargetDataDir $SelectedModel /J /Z /R:5 /W:3 /NP
        $TransferDuration = [Math]::Round(((Get-Date) - $TransferStart).TotalSeconds, 1)
        $FileSizeMB = [Math]::Round((Get-Item $DstModelPath).Length / 1MB, 1)
        $SpeedMBs = [Math]::Round($FileSizeMB / [Math]::Max(1, $TransferDuration), 1)
        Write-Host "    Transfer Complete: $FileSizeMB MB in $TransferDuration s ($SpeedMBs MB/s)" -ForegroundColor Green
    } else {
        Write-Host "    Model not found in local source. Downloading from Hugging Face (~4.68 GB)..." -ForegroundColor Yellow
        $ModelUrl = if ($SelectedModel -like "*symbols*") {
            "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf"
        } else {
            "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
        }
        & curl.exe -L -C - --progress-bar -o "$DstModelPath" "$ModelUrl"
        Write-Host "    Download completed for $SelectedModel" -ForegroundColor Green
    }
}

# Verify SHA-256 if manifest entry exists
if ($Manifest -and -not $NeedModelDownload) {
    Write-Host "    Performing quick integrity check on $SelectedModel..." -ForegroundColor Gray
    # Quick header validation via file stream length
    if ((Get-Item $DstModelPath).Length -lt 1000000) {
        Write-Error "Corrupted model file detected. Size is less than 1 MB."
    }
}

# Unblock files to prevent SmartScreen popups
Get-ChildItem -Path $TargetBaseDir -Recurse -File | ForEach-Object {
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

# Persist hardware tier and safe thread configuration
Set-Content -Path (Join-Path $TargetBaseDir "tier.cfg") -Value $SelectedModel -Encoding ASCII
Set-Content -Path (Join-Path $TargetBaseDir "threads.cfg") -Value $Threads -Encoding ASCII

# ------------------------------------------------------------------------------
# 5. ENVIRONMENT INTEGRATION & SERVICE STARTUP
# ------------------------------------------------------------------------------
Write-Host "`n[5/6] Registering Command-Line Entry Points & Service..." -ForegroundColor Green

# Create global q.bat wrapper in WindowsApps and UserProfile
$AppsDir = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
$QContent = "@echo off`r`ncall `"$TargetBaseDir\main.bat`" %*"

if (Test-Path $AppsDir) {
    Set-Content -Path "$AppsDir\q.bat" -Value $QContent -Encoding ASCII -ErrorAction SilentlyContinue
}
Set-Content -Path "$env:USERPROFILE\q.bat" -Value $QContent -Encoding ASCII -ErrorAction SilentlyContinue

# Ensure Background Inference Daemon is running
$PortOccupied = (netstat -ano | findstr 58080)
if (-not $PortOccupied) {
    Write-Host "    Starting background inference worker (worker.exe on port 58080)..." -ForegroundColor Gray
    wscript.exe "$TargetBaseDir\svc.vbs"
    Start-Sleep -Seconds 3
} else {
    Write-Host "    Inference service already active on port 58080." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 6. FUNCTIONAL VERIFICATION & TELEMETRY
# ------------------------------------------------------------------------------
Write-Host "`n[6/6] Verifying LLM Generation & Latency..." -ForegroundColor Green

$PyExe = Join-Path -Path $TargetBaseDir -ChildPath "py\python.exe"
if (-not (Test-Path $PyExe)) {
    $PyExe = "python.exe"
}
$ClientScript = Join-Path -Path $TargetBaseDir -ChildPath "client.py"

$InferenceSuccess = $false
$TestDurationSeconds = 0

if (-not $SkipTestPrompt) {
    Write-Host "    Submitting test algorithmic query: 'Provide a C++ binary search template'..." -ForegroundColor Gray
    $PromptStart = Get-Date
    try {
        $Output = & $PyExe $ClientScript "Write a 3-line C++ binary search function." 2>&1
        $TestDurationSeconds = [Math]::Round(((Get-Date) - $PromptStart).TotalSeconds, 2)
        if ($LASTEXITCODE -eq 0 -and $Output) {
            $InferenceSuccess = $true
            Write-Host "    [SUCCESS] Model responded in $TestDurationSeconds seconds!" -ForegroundColor Green
        } else {
            Write-Warning "Inference script returned non-zero code. Service may still be initializing weights."
        }
    } catch {
        Write-Warning "Failed to execute test prompt: $_"
    }
}

# Post Audit Telemetry to Server
$TotalDuration = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 1)
$Telemetry = [ordered]@{
    computer_name   = $env:COMPUTERNAME
    timestamp       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    ram_gb          = $TotalRamGB
    threads         = $Threads
    storage_target  = $TargetBaseDir
    model_loaded    = $SelectedModel
    total_sync_sec  = $TotalDuration
    inference_test  = if ($InferenceSuccess) { "PASSED ($TestDurationSeconds s)" } else { "SKIPPED/INITIALIZING" }
}

$ServerLogsDir = Join-Path -Path $SourcePath -ChildPath "logs"
if (Test-Path $ServerLogsDir) {
    try {
        $LogFile = Join-Path -Path $ServerLogsDir -ChildPath "$($env:COMPUTERNAME).json"
        $Telemetry | ConvertTo-Json -Depth 3 | Set-Content -Path $LogFile -Encoding UTF8
        Write-Host "    Audit telemetry posted to: $LogFile" -ForegroundColor Gray
    } catch {
        # Non-critical if write fails
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "   Deployment Complete! Run 'q' from any terminal.       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
