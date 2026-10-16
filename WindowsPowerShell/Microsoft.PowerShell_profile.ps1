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

$script:ExplorerSortAvailable = $false
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    try {
        if (-not ('ExplorerDirectoryFirstSorter' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.Collections;
using System.IO;
using System.Runtime.InteropServices;

public sealed class ExplorerDirectoryFirstSorter : IComparer {
    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int StrCmpLogicalW(string x, string y);

    private static string GetName(object item) {
        if (item == null) return String.Empty;
        FileSystemInfo file = item as FileSystemInfo;
        return file != null ? file.Name : item.ToString();
    }

    public int Compare(object x, object y) {
        bool xIsDirectory = x is DirectoryInfo;
        bool yIsDirectory = y is DirectoryInfo;
        if (xIsDirectory != yIsDirectory) {
            return xIsDirectory ? -1 : 1;
        }
        return StrCmpLogicalW(GetName(x), GetName(y));
    }
}
"@
        }
        $script:ExplorerSortAvailable = $true
    }
    catch {
        Write-Warning "Explorer natural sort unavailable: $($_.Exception.Message)"
    }
}

if (Test-Path Alias:ls) {
    Remove-Item Alias:ls -Force
}

function ls {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Position=0, ParameterSetName='Path')]
        [string[]]$Path,

        [Parameter(Mandatory=$true, ParameterSetName='LiteralPath')]
        [string[]]$LiteralPath,

        [string]$Filter,
        [string[]]$Include,
        [string[]]$Exclude,
        [switch]$Recurse,
        [int]$Depth,
        [switch]$Force,
        [switch]$Name,
        [switch]$File,
        [switch]$Directory,
        [switch]$Hidden,
        [switch]$ReadOnly,
        [switch]$System,
        [string]$Attributes
    )

    $gciParams = @{}
    foreach ($key in @('Path', 'LiteralPath', 'Filter', 'Include', 'Exclude',
                      'Recurse', 'Depth', 'Force', 'Name', 'File', 'Directory',
                      'Hidden', 'ReadOnly', 'System', 'Attributes')) {
        if ($PSBoundParameters.ContainsKey($key)) {
            $gciParams[$key] = $PSBoundParameters[$key]
        }
    }

    $items = @(Get-ChildItem @gciParams)
    if ($items.Count -gt 1) {
        if ($script:ExplorerSortAvailable) {
            [Array]::Sort([object[]]$items, [System.Collections.IComparer]([ExplorerDirectoryFirstSorter]::new()))
        } else {
            $items = @($items | Sort-Object -Property {
                if ($_ -is [System.IO.FileSystemInfo]) { $_.Name } else { [string]$_ }
            })
        }
    }

    foreach ($item in $items) {
        if ($item -is [System.IO.FileSystemInfo]) {
            $item.Name
        } else {
            [string]$item
        }
    }
}

function rmf {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string[]]$Path
    )

    process {
        foreach ($p in $Path) {
            if ($PSCmdlet.ShouldProcess($p, 'Remove recursively and forcibly')) {
                try {
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Warning "Could not remove '$p': $_"
                }
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

# ============================
# yt-dlp aliases
# ============================

$audioFormats = @('aac', 'best', 'flac', 'm4a', 'mp3', 'opus', 'vorbis', 'wav')
foreach ($format in $audioFormats) {
    $funcName = "yta-$format"
    $fmt = $format
    $scriptBlock = { yt-dlp --extract-audio --audio-format $fmt @args }.GetNewClosure()
    Set-Item -Path "Function:$funcName" -Value $scriptBlock -Force
}

function yt-best {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f 'bv*+ba/b' @Arguments
}

function ytv {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f 'bv' @Arguments
}

function yta {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f 'ba' @Arguments
}

function yt-playlist {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f 'bv*+ba/b' --continue --ignore-errors -o '%(autonumber)s-%(title)s [%(id)s].%(ext)s' @Arguments
}

function yt-mp4 {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -t mp4 @Arguments
}

function downloadchannel {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    yt-dlp -f 'bv*+ba/b' --continue --ignore-errors --no-overwrites -o '%(title)s [%(id)s].%(ext)s' @Arguments
}

# ============================
# Shell Behavior and Prompt
# ============================

# Import Chocolatey tab completion once, if available.
if ($env:ChocolateyInstall) {
    $ChocolateyProfile = Join-Path $env:ChocolateyInstall 'helpers\chocolateyProfile.psm1'
    if (Test-Path -LiteralPath $ChocolateyProfile) {
        Import-Module $ChocolateyProfile -ErrorAction SilentlyContinue
    }
}

function prompt {
    $e = [char]27
    "$e[1;36m$PWD $e[1;35m$([char]0x03BD)$e[0m "
}

Set-PSReadLineOption -PromptText ' '

Set-PSReadLineOption -Colors @{
    Keyword = 'Yellow'
}

# ============================
# Functions
# ============================

function extractframes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFile,

        [string]$OutputDir = ''
    )

    if (-not (Test-MediaTool 'ffmpeg')) { return }
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        Write-Error "Input file does not exist or is not a file: '$InputFile'"
        return
    }

    $fileItem = Get-Item -LiteralPath $InputFile

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $sanitizedName = $fileItem.BaseName -replace '[^\w\-\.]', '_'
        $baseDir = Join-Path $fileItem.DirectoryName "${sanitizedName}_frames"
        $OutputDir = $baseDir
        $number = 2
        while (Test-Path -LiteralPath $OutputDir) {
            $OutputDir = "${baseDir}_$number"
            $number++
        }
    } elseif (Test-Path -LiteralPath $OutputDir) {
        if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
            Write-Error "Output path already exists and is not a directory: '$OutputDir'"
            return
        }
        if (@(Get-ChildItem -LiteralPath $OutputDir -File -Filter 'frame_*.png').Count -gt 0) {
            Write-Error "Output directory already contains frame_*.png files. Use a new or empty directory: '$OutputDir'"
            return
        }
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction Stop | Out-Null
    }

    $resolvedOutput = (Get-Item -LiteralPath $OutputDir).FullName
    $outputPattern = Join-Path $resolvedOutput 'frame_%06d.png'
    Write-Host "Extracting non-consecutive-duplicate frames to '$resolvedOutput'..."

    $ffmpegArgs = @(
        '-nostdin', '-n', '-hide_banner', '-loglevel', 'error',
        '-i', $fileItem.FullName,
        '-vf', 'mpdecimate', '-fps_mode', 'vfr',
        '-compression_level', '6', '-pred', 'mixed',
        $outputPattern
    )
    & ffmpeg @ffmpegArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Frame extraction failed with exit code $LASTEXITCODE"
        return
    }

    $savedFiles = @(Get-ChildItem -LiteralPath $resolvedOutput -File -Filter 'frame_*.png')
    Write-Host "Done: $($savedFiles.Count) frames saved in $resolvedOutput" -ForegroundColor Green
}

function flipvid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,

        [ValidateSet('Default', 'Fast', 'Ultrafast', 'NVENC')]
        [string]$Speed = 'Default'
    )

    if (-not (Test-MediaTool 'ffmpeg')) { return }
    if (-not (Test-Path -LiteralPath $InputFilePath -PathType Leaf)) {
        Write-Error "Input file not found: '$InputFilePath'"
        return
    }

    $fileInfo = Get-Item -LiteralPath $InputFilePath
    $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)_flipped.mp4"
    if (Test-Path -LiteralPath $outputFile) {
        Write-Warning "Output already exists, refusing to overwrite: '$outputFile'"
        return
    }

    switch ($Speed) {
        'Fast'      { $extraArgs = @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18') }
        'Ultrafast' { $extraArgs = @('-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '23') }
        'NVENC'     { $extraArgs = @('-c:v', 'h264_nvenc', '-preset', 'p7', '-rc', 'vbr', '-cq', '19', '-b:v', '0') }
        default     { $extraArgs = @('-c:v', 'libx264', '-preset', 'medium', '-crf', '23') }
    }

    & ffmpeg -nostdin -n -hide_banner -loglevel error -i $fileInfo.FullName -vf 'hflip' @extraArgs -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart $outputFile

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Video flipped successfully -> $outputFile" -ForegroundColor Green
    } else {
        Write-Warning "Failed to flip video (exit code: $LASTEXITCODE)"
    }
}

function reversevid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$InputFilePath,

        [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'placebo')]
        [string]$Preset = 'veryfast',

        [ValidateRange(1, 60)]
        [int]$ChunkSeconds = 10
    )

    if (-not (Test-MediaTool 'ffmpeg')) { return }
    if (-not (Test-MediaTool 'ffprobe')) { return }
    if (-not (Test-Path -LiteralPath $InputFilePath -PathType Leaf)) {
        Write-Error "Input file not found: '$InputFilePath'"
        return
    }

    $fileInfo = Get-Item -LiteralPath $InputFilePath
    $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)_reversed.mp4"
    if (Test-Path -LiteralPath $outputFile) {
        Write-Warning "Output already exists, refusing to overwrite: '$outputFile'"
        return
    }

    $durationLines = @(& ffprobe -v error -show_entries format=duration -of 'default=noprint_wrappers=1:nokey=1' -i $fileInfo.FullName)
    $duration = 0.0
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($LASTEXITCODE -ne 0 -or $durationLines.Count -eq 0 -or
        -not [double]::TryParse([string]$durationLines[0], [System.Globalization.NumberStyles]::Float, $culture, [ref]$duration) -or
        $duration -le 0 -or [double]::IsInfinity($duration) -or [double]::IsNaN($duration)) {
        Write-Error "Could not read a valid duration from '$($fileInfo.FullName)'"
        return
    }

    $audioLines = @(& ffprobe -v error -select_streams a:0 -show_entries stream=index -of 'csv=p=0' -i $fileInfo.FullName)
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Could not inspect audio streams with ffprobe.'
        return
    }
    $hasAudio = ($audioLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$audioLines[0]))

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('Reverse-Video-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null

    try {
        $chunkCount = [int][Math]::Ceiling($duration / $ChunkSeconds)
        $chunkNames = New-Object 'System.Collections.Generic.List[string]'
        Write-Host "Reversing video in $chunkCount chunk(s) of up to $ChunkSeconds seconds..."

        for ($i = $chunkCount - 1; $i -ge 0; $i--) {
            $start = [double]$i * $ChunkSeconds
            $length = [Math]::Min($ChunkSeconds, $duration - $start)
            if ($length -le 0.000001) { continue }

            $startText = $start.ToString('0.######', $culture)
            $lengthText = $length.ToString('0.######', $culture)
            $partName = ('chunk_{0:D6}.mkv' -f $chunkNames.Count)
            $partPath = Join-Path $tempDir $partName

            $segmentArgs = @(
                '-nostdin', '-n', '-hide_banner', '-loglevel', 'error',
                '-ss', $startText, '-i', $fileInfo.FullName, '-t', $lengthText,
                '-map', '0:v:0'
            )
            if ($hasAudio) { $segmentArgs += @('-map', '0:a:0') }

            $segmentArgs += @(
                '-vf', 'reverse,setpts=PTS-STARTPTS,format=yuv420p',
                '-c:v', 'libx264', '-preset', $Preset, '-crf', '23'
            )
            if ($hasAudio) {
                $segmentArgs += @('-af', 'areverse,asetpts=PTS-STARTPTS', '-c:a', 'flac')
            } else {
                $segmentArgs += '-an'
            }
            $segmentArgs += @('-movflags', '+faststart', $partPath)

            & ffmpeg @segmentArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed reversing chunk $($chunkNames.Count + 1) (exit code: $LASTEXITCODE)"
                return
            }
            [void]$chunkNames.Add($partName)
        }

        $listPath = Join-Path $tempDir 'concat.txt'
        $listLines = @($chunkNames | ForEach-Object { "file '$_'" })
        [System.IO.File]::WriteAllLines($listPath, [string[]]$listLines, (New-Object System.Text.UTF8Encoding($false)))

        & ffmpeg -nostdin -n -hide_banner -loglevel error -f concat -safe 0 -i $listPath -c:v copy -c:a aac -b:a 192k -movflags +faststart $outputFile
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Video reversed successfully -> $outputFile" -ForegroundColor Green
        } else {
            Write-Warning "Failed to assemble reversed video (exit code: $LASTEXITCODE)"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-Mp4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName', 'PSPath')]
        [string[]]$InputFilePath,

        [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'placebo')]
        [string]$Preset = 'slow',

        [ValidateRange(0, 51)]
        [int]$CRF = 18
    )

    process {
        if (-not (Test-MediaTool 'ffmpeg')) { return }

        foreach ($path in $InputFilePath) {

            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $files = @(Get-Item -LiteralPath $path)
            } else {
                $files = @(Get-Item -Path $path -ErrorAction SilentlyContinue)
            }

            if ($files.Count -eq 0) {
                Write-Error "Input file not found or pattern matched no files: '$path'"
                continue
            }

            foreach ($fileInfo in $files) {
                if ($fileInfo.PSIsContainer) { continue }

                $suffix = if ($fileInfo.Extension -eq '.mp4') { '_converted.mp4' } else { '.mp4' }
                $outputFile = Join-Path $fileInfo.DirectoryName "$($fileInfo.BaseName)$suffix"
                if (Test-Path -LiteralPath $outputFile) {
                    Write-Warning "Output already exists, refusing to overwrite: '$outputFile'"
                    continue
                }

                Write-Host "Converting '$($fileInfo.Name)' to MP4..."
                & ffmpeg -nostdin -n -hide_banner -loglevel error -i $fileInfo.FullName -c:v libx264 -preset $Preset -crf $CRF -pix_fmt yuv420p -c:a aac -b:a 320k -movflags +faststart $outputFile

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Converted successfully -> $outputFile" -ForegroundColor Green
                } else {
                    Write-Error "Failed to convert '$($fileInfo.Name)' (exit code: $LASTEXITCODE)"
                }
            }
        }
    }
}

Set-Alias -Name mp4 -Value ConvertTo-Mp4 -Force