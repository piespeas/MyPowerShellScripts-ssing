$Accent      = "Magenta"
$AccentDark  = "DarkMagenta"
$Secondary   = "DarkGray"
$Primary     = "White"
$ErrorCol    = "Red"

Write-Host @"
meow
"@ -ForegroundColor $Accent

Write-Host "                          By AcousticVoid :3" -ForegroundColor $Secondary
Write-Host ""

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires Administrator privileges." -ForegroundColor $AccentDark
    Write-Host "Restarting as Administrator" -ForegroundColor $AccentDark
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "PowerShell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    $psi.Verb = "RunAs"
    
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
    catch {
        Write-Host "no admin" -ForegroundColor $ErrorCol
    }
}

$DownloadPath = "C:\Screenshare"
if (!(Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
}

function Add-DefenderExclusion {
    Write-Host "`nSetting up antivirus exclusion" -ForegroundColor $Accent
    Write-Host "Adding Windows Defender exclusion for $DownloadPath" -NoNewline -ForegroundColor $Secondary
    
    $success = $false
    
    try {
        if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
            $existingExclusions = (Get-MpPreference -ErrorAction Stop).ExclusionPath
            if ($existingExclusions -notcontains $DownloadPath) {
                Add-MpPreference -ExclusionPath $DownloadPath -ErrorAction Stop
            }
            Write-Host " Success" -ForegroundColor $Accent
            $success = $true
        }
    }
    catch { }
    
    if (-not $success) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths"
            if (Test-Path $regPath) {
                $existingValue = Get-ItemProperty -Path $regPath -Name $DownloadPath -ErrorAction SilentlyContinue
                if (-not $existingValue) {
                    New-ItemProperty -Path $regPath -Name $DownloadPath -Value 0 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
                }
                Write-Host " Success" -ForegroundColor $Accent
                $success = $true
            }
        }
        catch { }
    }
    
    if (-not $success) {
        try {
            $namespace = "root\Microsoft\Windows\Defender"
            if (Get-WmiObject -Namespace $namespace -List -ErrorAction SilentlyContinue) {
                $defender = Get-WmiObject -Namespace $namespace -Class "MSFT_MpPreference" -ErrorAction Stop
                $defender.AddExclusionPath($DownloadPath)
                Write-Host " Success" -ForegroundColor $Accent
                $success = $true
            }
        }
        catch { }
    }
    
    if (-not $success) {
        Write-Host " Failed" -ForegroundColor $ErrorCol
    }
    
    return $success
}

$exclusionAdded = Add-DefenderExclusion

if (-not $exclusionAdded) {
    Write-Host "`nCould not add automatic antivirus exclusion, you are prolly using some 3rd party av." -ForegroundColor $AccentDark
    Write-Host "`nContinuing with downloads (some might be deleted)" -ForegroundColor $Secondary
    Start-Sleep -Seconds 3
} else {
}

function Download-File {
    param([string]$Url, [string]$FileName, [string]$ToolName)
    
    try {
        $outputPath = Join-Path $DownloadPath $FileName
        Write-Host "  Downloading $ToolName" -NoNewline -ForegroundColor $Secondary
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $outputPath -UserAgent "PowerShell" -UseBasicParsing | Out-Null
        
        if ($FileName -like "*.zip") {
            $extractPath = Join-Path $DownloadPath ($FileName -replace '\.zip$', '')
            Expand-Archive -Path $outputPath -DestinationPath $extractPath -Force | Out-Null
            Remove-Item $outputPath -Force | Out-Null
        }
        Write-Host " Done" -ForegroundColor $Accent
        return $true
    }
    catch {
        Write-Host " Failed" -ForegroundColor $ErrorCol
        return $false
    }
    finally {
        $ProgressPreference = 'Continue'
    }
}

function Download-Tools {
    param([array]$Tools, [string]$CategoryName)
    
    $successCount = 0
    
    Write-Host "`nDownloading $CategoryName tools" -ForegroundColor $Accent
    foreach ($tool in $Tools) {
        if (Download-File -Url $tool.Url -FileName $tool.File -ToolName $tool.Name) {
            $successCount++
        }
    }
    
    Write-Host ($CategoryName + ": " + $successCount + "/" + $Tools.Count + " tools downloaded successfully") -ForegroundColor $Secondary
}

$installAllResponse = Read-Host "`nDo you want to download ALL tool categories? (Y/N)"
$installAll = $installAllResponse -match '^[Yy]'

if ($installAll) {
    Write-Host "`nDownloading all tool categories..." -ForegroundColor $Accent
    
    Download-Tools -Tools $spowksucksasscheeks -CategoryName "Spokwn's"
    Download-Tools -Tools $zimmermanTools -CategoryName "Zimmerman's"
    
    $runtimeResponse = Read-Host "`nWould you like to install the .NET Runtime (required for zimmerman) (Y/N)"
    if ($runtimeResponse -match '^[Yy]') {
        Download-File -Url "https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.306/dotnet-sdk-9.0.306-win-x64.exe" -FileName "dotnet-sdk-9.0.306-win-x64.exe" -ToolName ".NET Runtime"
    }
    
    Download-Tools -Tools $nirsoftTools -CategoryName "Nirsoft"
    Download-Tools -Tools $myTools -CategoryName "My"
    Download-Tools -Tools $otherTools -CategoryName "Other Common"
} else {
    Write-Host "`nSelect which categories to download:" -ForegroundColor $AccentDark
}

Write-Host "`nFor questions etc dm piespeas on discord" -ForegroundColor $Secondary
Write-Host "all is in: $DownloadPath" -ForegroundColor $Secondary