$startPath = "C:\Users"

if (-not (Test-Path $startPath)) {
    Write-Host "Path not found: $startPath" -ForegroundColor Red
    Read-Host "Press Enter to close"
    return
}

# Requires PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Parallel processing requires PowerShell 7 or higher." -ForegroundColor Red
    Write-Host "Download it at: https://aka.ms/powershell" -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    return
}

Write-Host "Finding files, it may take a few minutes..." -ForegroundColor Yellow

$gzFiles  = Get-ChildItem -Path $startPath -Recurse -Filter "*.gz"  -File -Force -ErrorAction SilentlyContinue
$logFiles = Get-ChildItem -Path $startPath -Recurse -Filter "*.log" -File -Force -ErrorAction SilentlyContinue
$allFiles = @($gzFiles) + @($logFiles)

Write-Host "Found $($allFiles.Count) files, scanning in parallel..." -ForegroundColor Yellow

$results = $allFiles | ForEach-Object -Parallel {
    $file = $_

    try {
        $content = $null
        $isGz    = $file.Extension -eq ".gz"

        if ($isGz) {
            $tempOutput = Join-Path $env:TEMP "$($file.BaseName)_$([guid]::NewGuid().ToString('N')).txt"

            try {
                $inputStream  = [System.IO.File]::OpenRead($file.FullName)
                $outputStream = [System.IO.File]::Create($tempOutput)
                $gzipStream   = New-Object System.IO.Compression.GZipStream(
                                    $inputStream,
                                    [System.IO.Compression.CompressionMode]::Decompress
                                )
                $gzipStream.CopyTo($outputStream)
            }
            finally {
                if ($gzipStream)   { $gzipStream.Close() }
                if ($outputStream) { $outputStream.Close() }
                if ($inputStream)  { $inputStream.Close() }
            }

            $content = Get-Content $tempOutput -Raw -ErrorAction SilentlyContinue
            Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
        }
        else {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        }

        $pattern = "Setting user:\s*(\S+)"
        if ($content -and $content -match $pattern) {
            [PSCustomObject]@{
                Username = $Matches[1]
                Path     = $file.FullName
            }
        }
    }
    catch {
        # Skip unreadable files silently
    }

} -ThrottleLimit 10

# Deduplicate and sort
$unique = $results |
    Where-Object { $_ -ne $null } |
    Sort-Object Username |
    Group-Object Username |
    ForEach-Object { $_.Group[0] }

if ($unique.Count -gt 0) {
    $termWidth  = $Host.UI.RawUI.WindowSize.Width
    $userColW   = 25
    $pathColW   = $termWidth - $userColW - 7
    $divider    = ("=" * ($userColW + $pathColW + 7))
    $rowDivider = ("-" * ($userColW + $pathColW + 7))

    Write-Host ""
    Write-Host $divider -ForegroundColor DarkGray
    Write-Host ("| {0,-$userColW} | {1,-$pathColW} |" -f "USERNAME", "PATH") -ForegroundColor White
    Write-Host $divider -ForegroundColor DarkGray

    foreach ($entry in $unique) {
        $username = $entry.Username
        $path     = $entry.Path

        if ($path.Length -gt $pathColW) {
            $path = "..." + $path.Substring($path.Length - ($pathColW - 3))
        }

        Write-Host ("| ")                          -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-$userColW}" -f $username) -ForegroundColor Cyan     -NoNewline
        Write-Host (" | ")                         -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-$pathColW}" -f $path)     -ForegroundColor White    -NoNewline
        Write-Host (" |")                          -ForegroundColor DarkGray

        Write-Host $rowDivider -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host ("  Total unique usernames found: {0}" -f $unique.Count) -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close"
}
else {
    Write-Host "No usernames found." -ForegroundColor Red
    Read-Host "Press Enter to close"
}