#───────────────────────────────────────────────────────────────────────────────
# STEP 1: CONFIGURATION
#───────────────────────────────────────────────────────────────────────────────

$folderPath      = 'ADD YOUR DESTINATION'    # Source folder
$outputDirectory = 'ADD YOUR DESTINATION'    # Destination
$clipCount       = 13                  # How many random files
$segmentLength   = 10                  # Seconds per clip

# Ensure output dir exists
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

#───────────────────────────────────────────────────────────────────────────────
# STEP 2: SELECT RANDOM VIDEO FILES
#───────────────────────────────────────────────────────────────────────────────

$videoFiles = Get-ChildItem -Path $folderPath -File -Recurse |
              Where-Object { $_.Extension -in '.mp4','.webm' } |
              Get-Random   -Count $clipCount

if ($videoFiles.Count -eq 0) {
    Throw "No .mp4/.webm files found in $folderPath"
}

Write-Host "STEP 2 → Randomly selected $($videoFiles.Count) files:`n"
$videoFiles | ForEach-Object { Write-Host "  $_.FullName" }
Write-Host ''

#───────────────────────────────────────────────────────────────────────────────
# STEP 2.1: VALIDATE SOURCE FILES (SKIP CORRUPT)
#───────────────────────────────────────────────────────────────────────────────

$validated = @()
foreach ($file in $videoFiles) {
    & ffmpeg -v error -i $file.FullName -f null - 2>$null
    if ($LASTEXITCODE -eq 0) {
        $validated += $file
    } else {
        Write-Warning "Skipping corrupt source: $($file.Name)"
    }
}

if ($validated.Count -eq 0) {
    Throw "All selected files are corrupt or unreadable."
}

$videoFiles = $validated
Write-Host "STEP 2.1 → ${videoFiles.Count} valid files remain after check.`n"

#───────────────────────────────────────────────────────────────────────────────
# STEP 3: EXTRACT 10-SECOND CLIPS WITH FORMAT HANDLING
#───────────────────────────────────────────────────────────────────────────────

$segments = @()
$counter  = 1

foreach ($file in $videoFiles) {
    # 3.1  Get duration
    $durationSec = (& ffprobe -v error `
                        -show_entries format=duration `
                        -of csv=p=0 `
                        $file.FullName).Trim() -as [double]
    $maxStart    = [math]::Max($durationSec - $segmentLength, 0)
    $startTime   = Get-Random -Minimum 0 -Maximum $maxStart

    # 3.2  Uniform naming: 40001.mp4 … 40013.mp4
    $segmentName = "400{0:D2}.mp4" -f $counter
    $segmentPath = Join-Path $outputDirectory $segmentName

    # 3.3  Extract or re-encode
    if ($file.Extension -eq '.webm') {
        & ffmpeg -y `
            -ss $startTime -i $file.FullName `
            -t  $segmentLength `
            -c:v libx264 -preset veryfast -crf 23 `
            -c:a aac     -b:a 128k `
            -movflags +faststart `
            $segmentPath
    } else {
        & ffmpeg -y `
            -ss $startTime -i $file.FullName `
            -t  $segmentLength `
            -c:v copy   -c:a copy `
            -avoid_negative_ts make_zero `
            -movflags +faststart `
            $segmentPath
    }

    # 3.4  Verify the new segment isn’t corrupt
    & ffmpeg -v error -i $segmentPath -f null - 2>$null
    if ($LASTEXITCODE -eq 0) {
        $segments += $segmentPath
        Write-Host "STEP 3 → Created segment #$counter: $segmentName"
    } else {
        Write-Warning "STEP 3 → Discarded corrupt segment: $segmentName"
        Remove-Item $segmentPath -ErrorAction SilentlyContinue
    }
    $counter++
}

if ($segments.Count -eq 0) {
    Throw "No valid segments to stitch."
}

Write-Host "`nSTEP 3 → ${segments.Count} total valid segments generated.`n"

#───────────────────────────────────────────────────────────────────────────────
# STEP 4: BUILD CONCATER LIST FILE
#───────────────────────────────────────────────────────────────────────────────

$listFile = Join-Path $outputDirectory 'segments.txt'
$segments | ForEach-Object {
    "file '$($_.Replace("'", "''"))'"
} | Out-File -FilePath $listFile -Encoding UTF8 -Force

Write-Host "STEP 4 → Wrote $($segments.Count) lines to $listFile"
Get-Content $listFile | ForEach-Object { Write-Host "   $_" }
Write-Host ''

#───────────────────────────────────────────────────────────────────────────────
# STEP 5: STITCH SEGMENTS WITH CONCAT DEMUXER
#───────────────────────────────────────────────────────────────────────────────

$tempCombined = Join-Path $outputDirectory 'temp_combined.mp4'

& ffmpeg -y -f concat -safe 0 `
    -i $listFile `
    -c copy `
    $tempCombined

if (-not (Test-Path $tempCombined)) {
    Throw "FFmpeg failed to produce combined file."
}

Write-Host "STEP 5 → Combined video created at $tempCombined`n"

#───────────────────────────────────────────────────────────────────────────────
# STEP 6: RENAME FINAL OUTPUT WITH NEXT INDEX
#───────────────────────────────────────────────────────────────────────────────

$existing = Get-ChildItem -Path $outputDirectory -Filter 'stitched_video_*.mp4'
$indices = $existing.BaseName | ForEach-Object {
    if ($_ -match 'stitched_video_(\d+)$') { [int]$Matches[1] }
}

$nextIndex = if ($indices) { ($indices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
$finalName = "stitched_video_$nextIndex.mp4"
$finalPath = Join-Path $outputDirectory $finalName

Rename-Item -Path $tempCombined -NewName $finalName
Write-Host "STEP 6 → Final video saved as $finalPath"