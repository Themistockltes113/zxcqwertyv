# Build script for LastChaos Client - Visual Studio 2022 x64
# Run this script from the repository root directory
# Usage: .\build_all_vs2022.ps1 [-Configuration Release] [-Platform x64] [-Clean]

param(
    [string]$Configuration = "USALIVE",
    [string]$Platform = "x64",
    [switch]$Clean = $false,
    [switch]$BuildLibsOnly = $false,
    [switch]$SkipLibs = $false
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host $msg -ForegroundColor Red }

# Find MSBuild
function Find-MSBuild {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $msbuildPath = & $vsWhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
        if ($msbuildPath) {
            return $msbuildPath
        }
    }
    
    # Fallback paths
    $fallbackPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    
    foreach ($path in $fallbackPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    throw "MSBuild not found. Please install Visual Studio 2022 with C++ workload."
}

# Check for DirectX SDK
function Check-DirectXSDK {
    $dxsdkDir = $env:DXSDK_DIR
    if (-not $dxsdkDir) {
        Write-Warn "WARNING: DXSDK_DIR environment variable not set."
        Write-Warn "The June 2010 DirectX SDK may be required for D3DX functions."
        Write-Warn "Download from: https://www.microsoft.com/en-us/download/details.aspx?id=6812"
        Write-Host ""
        return $false
    }
    
    if (-not (Test-Path $dxsdkDir)) {
        Write-Warn "WARNING: DXSDK_DIR points to non-existent path: $dxsdkDir"
        return $false
    }
    
    Write-Success "DirectX SDK found at: $dxsdkDir"
    return $true
}

# Build a project/solution
function Build-Project {
    param(
        [string]$ProjectPath,
        [string]$Config,
        [string]$Plat,
        [string]$MSBuild,
        [bool]$DoClean = $false
    )
    
    if (-not (Test-Path $ProjectPath)) {
        Write-Warn "  [SKIP] Project not found: $ProjectPath"
        return $false
    }
    
    $projectName = Split-Path $ProjectPath -Leaf
    Write-Info "  Building: $projectName ($Config|$Plat)"
    
    $target = if ($DoClean) { "Clean;Build" } else { "Build" }
    
    $args = @(
        $ProjectPath,
        "/t:$target",
        "/p:Configuration=$Config",
        "/p:Platform=$Plat",
        "/m",
        "/v:minimal",
        "/nologo"
    )
    
    & $MSBuild $args
    
    if ($LASTEXITCODE -ne 0) {
        Write-Err "  [FAILED] $projectName"
        return $false
    }
    
    Write-Success "  [OK] $projectName"
    return $true
}

# Main script
Write-Host "============================================================" -ForegroundColor White
Write-Host "LastChaos Client Build Script - Visual Studio 2022" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host "Configuration: $Configuration"
Write-Host "Platform: $Platform"
Write-Host "Clean Build: $Clean"
Write-Host ""

# Find MSBuild
Write-Info "[1/5] Locating MSBuild..."
try {
    $msbuild = Find-MSBuild
    Write-Success "  Found: $msbuild"
} catch {
    Write-Err $_.Exception.Message
    exit 1
}

# Check DirectX SDK
Write-Info "[2/5] Checking DirectX SDK..."
$hasDXSDK = Check-DirectXSDK

# Set working directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$clientSourceDir = Join-Path $scriptDir "Client Source"

if (-not (Test-Path $clientSourceDir)) {
    Write-Err "Client Source directory not found at: $clientSourceDir"
    exit 1
}

Set-Location $clientSourceDir

# Build third-party libraries
if (-not $SkipLibs) {
    Write-Info "[3/5] Building third-party libraries..."
    
    $libProjects = @(
        @{ Path = "3rdparty\zlib-1.2.8\zlib.vcxproj"; Config = "Release" },
        @{ Path = "3rdparty\tinyxml_2_6_2\tinyxml_lib.vcxproj"; Config = "Release" },
        @{ Path = "3rdparty\lpng163\libPng.vcxproj"; Config = "Release" },
        @{ Path = "Engine\lua\lua50.vcxproj"; Config = "Release" },
        @{ Path = "F_Socket\F_Socket_vc100.vcxproj"; Config = "Release" },
        @{ Path = "SharedMemory\SharedMemory.vcxproj"; Config = "Release" },
        @{ Path = "LCCrypt\LCCrypt.vcxproj"; Config = "Release" }
    )
    
    $libFailed = $false
    foreach ($lib in $libProjects) {
        $result = Build-Project -ProjectPath $lib.Path -Config $lib.Config -Plat $Platform -MSBuild $msbuild -DoClean $Clean
        if (-not $result) {
            $libFailed = $true
        }
    }
    
    if ($libFailed) {
        Write-Warn "  Some libraries failed to build. Continuing anyway..."
    }
} else {
    Write-Info "[3/5] Skipping third-party libraries (--SkipLibs)"
}

if ($BuildLibsOnly) {
    Write-Success "`nLibrary build complete!"
    exit 0
}

# Build main solution
Write-Info "[4/5] Building main solution..."

$mainSolution = "Build_2010.sln"
if (-not (Test-Path $mainSolution)) {
    Write-Err "Main solution not found: $mainSolution"
    exit 1
}

$result = Build-Project -ProjectPath $mainSolution -Config $Configuration -Plat $Platform -MSBuild $msbuild -DoClean $Clean

if (-not $result) {
    Write-Err "`nBuild FAILED!"
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  1. Missing DirectX SDK - Install June 2010 DirectX SDK"
    Write-Host "  2. Missing Windows SDK - Install Windows 10 SDK via Visual Studio Installer"
    Write-Host "  3. Missing MFC/ATL - Install via Visual Studio Installer (Desktop C++ workload)"
    Write-Host ""
    exit 1
}

# List output files
Write-Info "[5/5] Listing output files..."

$outputDirs = @(
    "Bin\x64",
    "Lib\VC100\x64"
)

Write-Host ""
Write-Host "Generated x64 binaries:" -ForegroundColor White

foreach ($dir in $outputDirs) {
    $fullPath = Join-Path $scriptDir $dir
    if (Test-Path $fullPath) {
        Write-Host "  $dir\" -ForegroundColor Cyan
        Get-ChildItem -Path $fullPath -Include "*.exe","*.dll","*.lib" -Recurse | ForEach-Object {
            $size = [math]::Round($_.Length / 1KB, 1)
            Write-Host "    $($_.Name) ($size KB)"
        }
    }
}

Write-Host ""
Write-Success "============================================================"
Write-Success "Build completed successfully!"
Write-Success "============================================================"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Copy the x64 binaries to your game directory"
Write-Host "  2. Ensure game assets are unpacked (not in .krf archives)"
Write-Host "  3. Run the client and check the log file for errors"
Write-Host ""

exit 0
