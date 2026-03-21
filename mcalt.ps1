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
                "Username" = $Matches[1]
                "Path"     = $file.FullName
            }
        }
    }
    catch {
        continue
    }
}

if ($results.Count -gt 0) {
    $seenUsernames = @{}
    $unique = @()

    $results | ForEach-Object {
        if (-not $seenUsernames.ContainsKey($_.Username)) {
            $seenUsernames[$_.Username] = $true
            $unique += $_
        }
    }

    $termWidth   = $Host.UI.RawUI.WindowSize.Width
    $userColW    = 25
    $pathColW    = $termWidth - $userColW - 7
    $divider     = ("=" * ($userColW + $pathColW + 7))
    $rowDivider  = ("-" * ($userColW + $pathColW + 7))

    Write-Host ""
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ("| {0,-$userColW} | {1,-$pathColW} |" -f "USERNAME", "PATH") -ForegroundColor White
    Write-Host $divider -ForegroundColor DarkGray

    foreach ($entry in $unique) {
        $username = $entry.Username
        $path     = $entry.Path

        # Truncate path if too long
        if ($path.Length -gt $pathColW) {
            $path = "..." + $path.Substring($path.Length - ($pathColW - 3))
        }

        Write-Host ("| " ) -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-$userColW}" -f $username) -ForegroundColor Cyan -NoNewline
        Write-Host (" | ") -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-$pathColW}" -f $path) -ForegroundColor White -NoNewline
        Write-Host (" |") -ForegroundColor DarkGray

        Write-Host $rowDivider -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host ("  Total unique usernames found: {0}" -f $unique.Count) -ForegroundColor Yellow
    Write-Host ""
}
