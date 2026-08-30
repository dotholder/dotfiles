# ============================
# Aliases
# ============================

# Package management
function update {
    choco upgrade all -y
}
function install {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PackageName)
    choco install $PackageName -y
}
function remove {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PackageName)
    choco uninstall $PackageName -y
}
function search {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PackageName)
    choco search $PackageName
}

# Navigation & files
function .. { 
    Set-Location .. 
}

if (Test-Path Alias:ls) {
    Remove-Item Alias:ls -Force
}

function ls {
    Get-ChildItem -Name $args
}

function rmf {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]$Path
    )

    begin {
        $ErrorActionPreference = 'Continue'
    }

    process {
        foreach ($p in $Path) {
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not remove $p completely: $_"
            }
        }
    }
}

# Git aliases
function dotfiles {
    git clone https://github.com/dotholder/dotfiles.git
}

# System commands
function restart { 
    Restart-Computer -Force 
}
function poweroff { 
    Stop-Computer -Force 
}

function info { 
    systeminfo 
}

# yt-dlp aliases
$audioFormats = @('aac', 'best', 'flac', 'm4a', 'mp3', 'opus', 'vorbis', 'wav')

foreach ($format in $audioFormats) {
    $funcName = "yta-$format"
    $fmt = $format

    Set-Item "Function:$funcName" -Value {
        yt-dlp --extract-audio --audio-format $fmt @args
    }.GetNewClosure() -Force
}

function yt-best {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-dlp -f bestvideo+bestaudio @Arguments
}

function ytv {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-dlp -f bestvideo @Arguments
}

function yta {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-dlp -f bestaudio @Arguments
}

function yt-playlist {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f bestvideo+bestaudio --continue --ignore-errors -o '%(autonumber)s-%(title)s.%(ext)s' @Arguments
}

function ytmp4 {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 @Arguments
}

function downloadchannel {
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-dlp -f bestvideo+bestaudio --continue --ignore-errors --no-overwrites -o "%(title)s.%(ext)s" @Arguments
}

# ============================
# Shell Behavior and Prompt
# ============================

# Import the Chocolatey Profile to enable tab-completions
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module $ChocolateyProfile
}

# Shell prompt
function prompt {
    $ESC = [char]27
    $username = $env:USERNAME
    $hostname = $env:COMPUTERNAME
    $currPath = (Get-Location).Path
    $location = Split-Path -Leaf -Path $currPath
    if ([string]::IsNullOrWhiteSpace($location)) { $location = $currPath }
    
    "$ESC[1;31m[$ESC[33m$username$ESC[32m@$ESC[34m$hostname $ESC[35m$location$ESC[31m]$ESC[37m$ $ESC[0m"
}

# ====================
# Functions
# ====================

# Video frame extractor
function Extract-Frames {
    param(
        [string]$InputFile,
        [string]$OutputDir = ""
    )

    if (-not $InputFile) {
        Write-Error "Usage: Extract-Frames -InputFile <video_file> [-OutputDir <output_dir>]"
        return
    }

    if (-not (Test-Path -LiteralPath $InputFile)) {
        $cleanedPath = $InputFile -replace '`([\[\]])', '$1'
        if (Test-Path -LiteralPath $cleanedPath) {
            $InputFile = $cleanedPath
        } else {
            Write-Error "Error: Input file '$InputFile' does not exist"
            return
        }
    }

    if (-not $OutputDir) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
        $sanitizedName = $baseName -replace '[^\w\-\.]', '_'
        $OutputDir = Join-Path (Get-Location) "${sanitizedName}_frames"
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $resolvedInput = (Convert-Path -LiteralPath $InputFile)
    $resolvedOutput = (Convert-Path -LiteralPath $OutputDir)

    Write-Host "Extracting frames to $resolvedOutput..."

    $outputPattern = Join-Path $resolvedOutput "frame_%06d.png"
    
    $ffmpegArgs = @(
        "-hide_banner"
        "-loglevel", "error"
        "-i", $resolvedInput
        "-vf", "mpdecimate,setpts=N/FRAME_RATE/TB"
        "-fps_mode", "vfr"
        "-compression_level", "6"
        "-pred", "mixed"
        $outputPattern
    )
    
    & ffmpeg @ffmpegArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$([char]0x274C) Extraction failed"
        return
    }

    $savedFiles = Get-ChildItem -LiteralPath $resolvedOutput -Filter "frame_*.png" | Sort-Object Name
    $totalExtracted = $savedFiles.Count
    
    if ($totalExtracted -eq 0) {
        Write-Host "$([char]0x274C) No frames were extracted."
        return
    }

    Write-Host "Checking checksums for $totalExtracted frames..."

    $seenHashes = @{}
    $deletedCount = 0

    foreach ($file in $savedFiles) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash

        if ($seenHashes.ContainsKey($hash)) {
            Remove-Item -LiteralPath $file.FullName -Force
            $deletedCount++
        } else {
            $seenHashes[$hash] = $file.FullName
        }
    }

    $remainingCount = $totalExtracted - $deletedCount
    Write-Host "$([char]0x2705) Done: $remainingCount unique frames saved ($deletedCount duplicates removed) in $resolvedOutput"
}

# Video flipper
function Flip-Video {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InputFilePath,

        [ValidateSet("Default", "Fast", "Ultrafast", "NVENC")]
        [string]$Speed = "Default"
    )

    try {
        $cleanPath = $InputFilePath.Trim()

        if (-not (Test-Path $cleanPath)) {
            Write-Host "$([char]0x274C) Input file not found: $cleanPath"
            return
        }

        $fileInfo = Get-Item $cleanPath
        $directory = $fileInfo.DirectoryName
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.Name)
        $extension = $fileInfo.Extension
        $outputFile = Join-Path $directory "${nameWithoutExt}_flipped${extension}"

        Write-Host "Flipping video horizontally..."
        Write-Host "Input: $($fileInfo.FullName)"
        Write-Host "Output: $outputFile"
        Write-Host "Speed mode: $Speed"

        switch ($Speed) {
            "Fast"      { $extraArgs = @("-c:v", "libx264", "-preset", "veryfast", "-crf", "18") }
            "Ultrafast" { $extraArgs = @("-c:v", "libx264", "-preset", "ultrafast", "-crf", "23") }
            "NVENC"     { $extraArgs = @("-c:v", "h264_nvenc", "-preset", "p7", "-cq", "19") }
            default     { $extraArgs = @() }
        }

        & ffmpeg -i "$($fileInfo.FullName)" -vf "hflip" -c:a copy @extraArgs "$outputFile"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$([char]0x2705) Video flipped successfully"
        } else {
            Write-Host "$([char]0x274C) Failed to flip video (Exit code: $LASTEXITCODE)"
        }
    }
    catch {
        Write-Host "$([char]0x274C) Error: $_"
    }
}

# Video reverser
function Reverse-Video {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InputFilePath,
        [string]$Preset = "veryfast"  # Options: ultrafast, superfast, veryfast, fast, medium (default), etc.
    )

    try {
        $cleanPath = $InputFilePath.Trim()

        if (-not (Test-Path $cleanPath)) {
            Write-Host "$([char]0x274C) Input file not found: $cleanPath"
            return
        }

        $fileInfo = Get-Item $cleanPath
        $directory = $fileInfo.DirectoryName
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.Name)
        $extension = $fileInfo.Extension

        $outputFile = Join-Path $directory "${nameWithoutExt}_reversed${extension}"

        Write-Host "Reversing video (using preset: $Preset)..."
        Write-Host "Input: $($fileInfo.FullName)"
        Write-Host "Output: $outputFile"

        & ffmpeg -i "$($fileInfo.FullName)" -vf "reverse" -af "areverse" -c:v libx264 -preset $Preset -crf 23 -c:a aac "$outputFile"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$([char]0x2705) Video reversed successfully"
        } else {
            Write-Host "$([char]0x274C) Failed to reverse video (Exit code: $LASTEXITCODE)"
        }
    }
    catch {
        Write-Host "$([char]0x274C) Error: $_"
    }
}

# MP4 Video Converter
function mp4 {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,

        [string]$Preset = "medium",  # Options: ultrafast, superfast, veryfast, fast, medium, slow
        [int]$CRF = 23              # Lower = higher quality/larger file (18-28 is sweet spot)
    )

    try {
        $cleanPath = $InputFilePath.Trim()

        if (-not (Test-Path $cleanPath)) {
            Write-Host "$([char]0x274C) Input file not found: $cleanPath"
            return
        }

        $fileInfo = Get-Item $cleanPath
        $directory = $fileInfo.DirectoryName
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.Name)
        $extension = $fileInfo.Extension.ToLower()

        if ($extension -eq ".mp4") {
            $outputFile = Join-Path $directory "${nameWithoutExt}_converted.mp4"
        } else {
            $outputFile = Join-Path $directory "${nameWithoutExt}.mp4"
        }

        Write-Host "Converting '$($fileInfo.Name)' to MP4..."
        Write-Host "Output: $outputFile"

        & ffmpeg -i "$($fileInfo.FullName)" -c:v libx264 -preset $Preset -crf $CRF -c:a aac -movflags +faststart "$outputFile"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$([char]0x2705) Video converted to MP4 successfully!"
        } else {
            Write-Host "$([char]0x274C) Failed to convert video (Exit code: $LASTEXITCODE)"
        }
    }
    catch {
        Write-Host "$([char]0x274C) Error: $_"
    }
}
