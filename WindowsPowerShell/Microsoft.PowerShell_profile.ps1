# ============================
# Aliases
# ============================

# Package management
function update {
    choco upgrade all -y
}
function install {
    param([string]$PackageName)
    choco install $PackageName -y
}
function remove {
    param([string]$PackageName)
    choco uninstall $PackageName -y
}
function search {
    param([string]$PackageName)
    choco search $PackageName
}

# Navigation & files
function .. { 
    Set-Location .. 
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
                Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
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
$audioFormats = @{
    'aac'    = '--extract-audio --audio-format aac'
    'best'   = '--extract-audio --audio-format best'
    'flac'   = '--extract-audio --audio-format flac'
    'm4a'    = '--extract-audio --audio-format m4a'
    'mp3'    = '--extract-audio --audio-format mp3'
    'opus'   = '--extract-audio --audio-format opus'
    'vorbis' = '--extract-audio --audio-format vorbis'
    'wav'    = '--extract-audio --audio-format wav'
}

foreach ($format in $audioFormats.Keys) {
    $funcName = "Download-YTAudio$format"
    $options  = $audioFormats[$format]

    $scriptBlock = [ScriptBlock]::Create("yt-dlp $options @args")
    Set-Item -Path Function:$funcName -Value $scriptBlock -Force

    New-Alias -Name "yta-$format" -Value $funcName -Force
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
    param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
    yt-best -cio '%(autonumber)s-%(title)s.%(ext)s' @Arguments
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
    $location = Split-Path -Leaf -Path (Get-Location)
    
    "$ESC[1;31m[$ESC[33m$username$ESC[32m@$ESC[34m$hostname $ESC[35m$location$ESC[31m]$ESC[37m$ $ESC[0m"
}

# ====================
# Scripts
# ====================

# Archive extractor
function Extract-Archive {
    param([string]$Path)

    if (!(Test-Path $Path -PathType Leaf)) {
        Write-Error "'$Path' is not a valid file"
        return
    }

    $dest = Split-Path -Parent $Path
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    switch ($extension) {
        ".zip"     { tar -xf $Path -C $dest }
        ".tar"     { tar -xf $Path -C $dest }
        ".tar.gz"  { tar -xf $Path -C $dest }
        ".tgz"     { tar -xf $Path -C $dest }
        ".tar.bz2" { tar -xf $Path -C $dest }
        ".tbz2"    { tar -xf $Path -C $dest }
        ".tar.xz"  { tar -xf $Path -C $dest }
        ".gz"      { 7z x $Path -o"$dest" -y }
        ".bz2"     { 7z x $Path -o"$dest" -y }
        ".xz"      { 7z x $Path -o"$dest" -y }
        ".rar"     { 7z x $Path -o"$dest" -y }
        ".7z"      { 7z x $Path -o"$dest" -y }
        default    { Write-Error "'$Path' cannot be extracted" }
    }
}

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

    if (-not (Test-Path $InputFile)) {
        Write-Error "Error: Input file '$InputFile' does not exist"
        return
    }

    if (-not $OutputDir) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
        $sanitizedName = $baseName -replace '[^\w\-\.]', '_'
        $OutputDir = Join-Path (Get-Location) "${sanitizedName}_frames"
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $resolvedInput = (Resolve-Path $InputFile).Path
    $resolvedOutput = (Resolve-Path $OutputDir).Path

    Write-Host "Extracting frames to $resolvedOutput ..."

    $outputPattern = Join-Path $resolvedOutput "frame_%06d.png"
    
    $ffmpegArgs = @(
        "-hide_banner"
        "-loglevel", "error"
        "-i", $resolvedInput
        "-compression_level", "6"
        "-pred", "mixed"
        $outputPattern
    )
    
    & ffmpeg @ffmpegArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$([char]0x274C) Extraction failed"
        return
    }

    Write-Host "$([char]0x2705) Extraction complete"

    # --- Duplicate removal and renumbering ---
    $frameFiles = Get-ChildItem -Path $resolvedOutput -Filter "frame_*.png"

    if ($frameFiles.Count -eq 0) {
        Write-Host "No frames were extracted."
        return
    }

    Write-Host "Checking for exact duplicate frames (pixel-for-pixel identical)..."

    $initialCount = $frameFiles.Count
    $frameFiles = $frameFiles | Sort-Object Name

    $seen = @{}
    $dupeCount = 0

    foreach ($file in $frameFiles) {
        try {
            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
            if ($seen.ContainsKey($hash)) {
                Remove-Item -Path $file.FullName -Force
                $dupeCount++
            } else {
                $seen[$hash] = $null
            }
        } catch {
            Write-Warning "Failed to hash file: $($file.Name)"
        }
    }

    if ($dupeCount -gt 0) {
        Write-Host "Deleted $dupeCount exact duplicate frames."

        Write-Host "Renumbering remaining frames sequentially..."
        $remainingFiles = Get-ChildItem -Path $resolvedOutput -Filter "frame_*.png" | Sort-Object Name
        $index = 1
        foreach ($file in $remainingFiles) {
            $newName = "frame_{0:000000}.png" -f $index
            if ($file.Name -ne $newName) {
                Rename-Item -Path $file.FullName -NewName $newName -Force
            }
            $index++
        }

        $finalCount = $remainingFiles.Count
    } else {
        Write-Host "No exact duplicates found."
        $finalCount = $initialCount
    }

    Write-Host "Done: $finalCount unique frames saved in $resolvedOutput"
}

#Video flipper
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
            "Fast"     { $extraArgs = @("-c:v", "libx264", "-preset", "veryfast", "-crf", "18") }
            "Ultrafast"{ $extraArgs = @("-c:v", "libx264", "-preset", "ultrafast", "-crf", "23") }
            "NVENC"    { $extraArgs = @("-hwaccel", "cuda", "-hwaccel_output_format", "cuda", "-c:v", "h264_nvenc", "-preset", "p7", "-cq", "19") }
            default    { $extraArgs = @() }  # original behavior
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