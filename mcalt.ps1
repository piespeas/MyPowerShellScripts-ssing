$startPath = "C:\Users"

if (-not (Test-Path $startPath)) {
    exit
}

Write-Host "Finding usernames, It may take a few minutes..." -ForegroundColor Yellow

$gzFiles = Get-ChildItem -Path $startPath -Recurse -Filter "*.gz" -File -Force -ErrorAction SilentlyContinue
$logFiles = Get-ChildItem -Path $startPath -Recurse -Filter "*.log" -File -Force -ErrorAction SilentlyContinue
$allFiles = @($gzFiles) + @($logFiles)

$results = @()

foreach ($file in $allFiles) {
    try {
        $content = $null
        $isGz = $file.Extension -eq ".gz"

        if ($isGz) {
            $tempFileName = "$($file.BaseName)_temp_$([guid]::NewGuid().ToString('N')).txt"
            $tempOutput = Join-Path $file.DirectoryName $tempFileName

            $inputStream = [System.IO.File]::OpenRead($file.FullName)
            $outputStream = [System.IO.File]::Create($tempOutput)
            $gzipStream = New-Object System.IO.Compression.GZipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)

            $gzipStream.CopyTo($outputStream)

            $gzipStream.Close()
            $outputStream.Close()
            $inputStream.Close()

            $content = Get-Content $tempOutput -Raw -ErrorAction SilentlyContinue
            Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
        } else {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        }

        $pattern = "Setting user:\s*(\S+)"
        if ($content -and $content -match $pattern) {
            $results += [PSCustomObject]@{
                "Usernames" = $Matches[1]
                "Path" = $file.FullName
            }
        }
    }
    catch {
        continue
    }
}

if ($results.Count -gt 0) {
    $seenUsernames = @{}
    $results | ForEach-Object {
        if (-not $seenUsernames.ContainsKey($_.Usernames)) {
            $seenUsernames[$_.Usernames] = $true
            Write-Host ("{0,-20}" -f $_.Usernames) -ForegroundColor Cyan -NoNewline
            Write-Host $_.Path -ForegroundColor White
        }
    }
}
