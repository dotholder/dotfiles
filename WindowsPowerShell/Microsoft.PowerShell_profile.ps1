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

# ============================
# Navigation & File Management
# ============================

function .. { Set-Location .. }

if (Test-Path Alias:ls) {
    Remove-Item Alias:ls -Force
}

if (-not ('ExplorerSorter' -as [type])) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    using System.Collections;
    using System.Collections.Generic;

    public class ExplorerSorter : IComparer, IComparer<object> {
        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        public static extern int StrCmpLogicalW(string x, string y);

        public int Compare(object x, object y) {
            string sx = x?.ToString();
            string sy = y?.ToString();
            return StrCmpLogicalW(sx, sy);
        }
    }
"@
}

function ls {
    $items = Get-ChildItem @args
    if ($items.Count -gt 1) {
        $sorter = [ExplorerSorter]::new()
        [Array]::Sort($items, [System.Comparison[object]]{ param($x, $y) $sorter.Compare($x.Name, $y.Name) })
    }
    $items
}

function rmf {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string[]]$Path
    )

    process {
        foreach ($p in $Path) {
            try {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not remove '$p': $_"
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
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f bestvideo+bestaudio @Arguments
}

function ytv {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f bestvideo @Arguments
}

function yta {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f bestaudio @Arguments
}

function yt-playlist {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f bestvideo+bestaudio --continue --ignore-errors -o '%(autonumber)s-%(title)s.%(ext)s' @Arguments
}

function yt-mp4 {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 @Arguments
}

function downloadchannel {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
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
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path -LiteralPath $ChocolateyProfile) {
    Import-Module $ChocolateyProfile -ErrorAction SilentlyContinue
}

function prompt {
    $e = [char]27
    "$e[1;36m$PWD $e[1;35mν $e[0m"
}

# ============================
# Functions
# ============================

function Extract-Frames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFile,

        [string]$OutputDir = ""
    )

    if (-not (Test-Path -LiteralPath $InputFile)) {
        Write-Error "Error: Input file '$InputFile' does not exist."
        return
    }

    $fileItem = Get-Item -LiteralPath $InputFile

    if (-not $OutputDir) {
        $sanitizedName = $fileItem.BaseName -replace '[^\w\-\.]', '_'
        $OutputDir = Join-Path $fileItem.DirectoryName "${sanitizedName}_frames"
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $resolvedInput = $fileItem.FullName
    $resolvedOutput = (Get-Item -LiteralPath $OutputDir).FullName

    Write-Host "Extracting unique frames to '$resolvedOutput'..."

    $outputPattern = Join-Path $resolvedOutput "frame_%06d.png"
    
    $ffmpegArgs = @(
        "-y"
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
        Write-Warning "Extraction failed with exit code $LASTEXITCODE"
        return
    }

    $savedFiles = Get-ChildItem -LiteralPath $resolvedOutput -Filter "frame_*.png"
    Write-Host "$([char]0x2705) Done: $($savedFiles.Count) frames saved in $resolvedOutput"
}

function Flip-Video {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,

        [ValidateSet("Default", "Fast", "Ultrafast", "NVENC")]
        [string]$Speed = "Default"
    )

    if (-not (Test-Path -LiteralPath $InputFilePath)) {
        Write-Host "$([char]0x274C) Input file not found: $InputFilePath"
        return
    }

    $fileInfo = Get-Item -LiteralPath $InputFilePath
    $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)_flipped$($fileInfo.Extension)"

    switch ($Speed) {
        "Fast"      { $extraArgs = @("-c:v", "libx264", "-preset", "veryfast", "-crf", "18") }
        "Ultrafast" { $extraArgs = @("-c:v", "libx264", "-preset", "ultrafast", "-crf", "23") }
        "NVENC"     { $extraArgs = @("-c:v", "h264_nvenc", "-preset", "p7", "-cq", "19") }
        default     { $extraArgs = @("-c:v", "libx264") }
    }

    & ffmpeg -y -i $fileInfo.FullName -vf "hflip" @extraArgs -c:a copy "$outputFile"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "$([char]0x2705) Video flipped successfully -> $outputFile"
    } else {
        Write-Host "$([char]0x274C) Failed to flip video (Exit code: $LASTEXITCODE)"
    }
}

function Reverse-Video {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,
        [string]$Preset = "veryfast"
    )

    if (-not (Test-Path -LiteralPath $InputFilePath)) {
        Write-Host "$([char]0x274C) Input file not found: $InputFilePath"
        return
    }

    $fileInfo = Get-Item -LiteralPath $InputFilePath
    $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)_reversed$($fileInfo.Extension)"

    Write-Host "Reversing video (using preset: $Preset)..."

    & ffmpeg -y -i $fileInfo.FullName -vf "reverse" -af "areverse" -c:v libx264 -preset $Preset -crf 23 -c:a aac "$outputFile"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "$([char]0x2705) Video reversed successfully -> $outputFile"
    } else {
        Write-Host "$([char]0x274C) Failed to reverse video (Exit code: $LASTEXITCODE)"
    }
}

function ConvertTo-Mp4 {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,

        [string]$Preset = "medium",
        [int]$CRF = 23
    )

    if (-not (Test-Path -LiteralPath $InputFilePath)) {
        Write-Host "$([char]0x274C) Input file not found: $InputFilePath"
        return
    }

    $fileInfo = Get-Item -LiteralPath $InputFilePath
    $suffix = if ($fileInfo.Extension -eq ".mp4") { "_converted.mp4" } else { ".mp4" }
    $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)$suffix"

    Write-Host "Converting '$($fileInfo.Name)' to MP4..."

    & ffmpeg -y -i $fileInfo.FullName -c:v libx264 -preset $Preset -crf $CRF -c:a aac -movflags +faststart "$outputFile"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "$([char]0x2705) Video converted to MP4 successfully -> $outputFile"
    } else {
        Write-Host "$([char]0x274C) Failed to convert video (Exit code: $LASTEXITCODE)"
    }
}

Set-Alias -Name mp4 -Value ConvertTo-Mp4 -Force