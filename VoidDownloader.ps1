$accent = "DarkCyan"
$success = "Green"
$fail = "Red"
$neutral = "Gray"
$highlight = "White"

function Write-Divider {
    param([string]$Label)
    $width = 54
    $inner = "[ $Label ]"
    $sides = [math]::Floor(($width - $inner.Length) / 2)
    $line = ("═" * $sides) + $inner + ("═" * ($width - $sides - $inner.Length))
    Write-Host "`n$line" -ForegroundColor $accent
}

function Write-Summary {
    param([int]$Downloaded, [int]$Total, [string]$Path)
    Write-Host ""
    Write-Host "┌──────────────────────────────────────┐" -ForegroundColor $accent
    Write-Host ("│  Tools Downloaded : {0,-19}│" -f "$Downloaded/$Total") -ForegroundColor $highlight
    Write-Host ("│  Location        : {0,-19}│" -f $Path) -ForegroundColor $highlight
    Write-Host ("│  Status          : {0,-19}│" -f $(if ($Downloaded -eq $Total) { "Complete" } else { "Done (with failures)" })) -ForegroundColor $highlight
    Write-Host "└──────────────────────────────────────┘" -ForegroundColor $accent
}

Clear-Host

try { $host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(220, 9999) } catch {}

Write-Host @"

  █████╗  ██████╗ ██████╗ ██╗   ██╗███████╗████████╗██╗ ██████╗    ██╗   ██╗ ██████╗ ██╗██████╗ 
 ██╔══██╗██╔════╝██╔═══██╗██║   ██║██╔════╝╚══██╔══╝██║██╔════╝    ██║   ██║██╔═══██╗██║██╔══██╗
 ███████║██║     ██║   ██║██║   ██║███████╗   ██║   ██║██║         ██║   ██║██║   ██║██║██║  ██║
 ██╔══██║██║     ██║   ██║██║   ██║╚════██║   ██║   ██║██║         ╚██╗ ██╔╝██║   ██║██║██║  ██║
 ██║  ██║╚██████╗╚██████╔╝╚██████╔╝███████║   ██║   ██║╚██████╗     ╚████╔╝ ╚██████╔╝██║██████╔╝
 ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   ╚═╝ ╚═════╝     ╚═══╝   ╚═════╝ ╚═╝╚═════╝ 

"@ -ForegroundColor $accent

Write-Host "  ══════════════════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $neutral
Write-Host "                                    Screenshare Forensics Toolkit" -ForegroundColor $neutral
Write-Host "  ══════════════════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $neutral
Write-Host ""

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Administrator privileges required." -ForegroundColor Yellow
    Write-Host "  Restarting as Administrator..." -ForegroundColor Yellow

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "PowerShell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    $psi.Verb = "RunAs"

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
    catch {
        Write-Host "  Failed to elevate privileges." -ForegroundColor $fail
    }
}

$DownloadPath = "C:\Screenshare"
if (!(Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
}

function Add-DefenderExclusion {
    Write-Divider "DEFENDER EXCLUSION"
    Write-Host "  Adding exclusion for $DownloadPath" -NoNewline -ForegroundColor $neutral

    $succeeded = $false

    try {
        if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
            $existing = (Get-MpPreference -ErrorAction Stop).ExclusionPath
            if ($existing -notcontains $DownloadPath) {
                Add-MpPreference -ExclusionPath $DownloadPath -ErrorAction Stop
            }
            Write-Host "  OK" -ForegroundColor $success
            $succeeded = $true
        }
    } catch {}

    if (-not $succeeded) {
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths"
            if (Test-Path $regPath) {
                $existing = Get-ItemProperty -Path $regPath -Name $DownloadPath -ErrorAction SilentlyContinue
                if (-not $existing) {
                    New-ItemProperty -Path $regPath -Name $DownloadPath -Value 0 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
                }
                Write-Host "  OK" -ForegroundColor $success
                $succeeded = $true
            }
        } catch {}
    }

    if (-not $succeeded) {
        try {
            $ns = "root\Microsoft\Windows\Defender"
            if (Get-WmiObject -Namespace $ns -List -ErrorAction SilentlyContinue) {
                $defender = Get-WmiObject -Namespace $ns -Class "MSFT_MpPreference" -ErrorAction Stop
                $defender.AddExclusionPath($DownloadPath)
                Write-Host "  OK" -ForegroundColor $success
                $succeeded = $true
            }
        } catch {}
    }

    if (-not $succeeded) {
        Write-Host "  Failed" -ForegroundColor $fail
        Write-Host "  Third-party AV detected. Some files may be removed." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }

    return $succeeded
}

$script:totalDownloaded = 0
$script:totalFailed = 0

function Download-File {
    param([string]$Url, [string]$FileName, [string]$ToolName, [int]$Index, [int]$Total)

    try {
        $outputPath = Join-Path $DownloadPath $FileName
        Write-Host ("  [{0,2}/{1}] {2}" -f $Index, $Total, $ToolName) -NoNewline -ForegroundColor $neutral
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $outputPath -UserAgent "PowerShell" -UseBasicParsing | Out-Null

        if ($FileName -like "*.zip") {
            $extractPath = Join-Path $DownloadPath ($FileName -replace '\.zip$', '')
            Expand-Archive -Path $outputPath -DestinationPath $extractPath -Force | Out-Null
            Remove-Item $outputPath -Force | Out-Null
        }

        Write-Host "  Done" -ForegroundColor $success
        $script:totalDownloaded++
        return $true
    }
    catch {
        Write-Host "  Failed" -ForegroundColor $fail
        $script:totalFailed++
        return $false
    }
    finally {
        $ProgressPreference = 'Continue'
    }
}

$allTools = @(
    @{ Name="Kernel Live Dump Tool";       Url="https://github.com/spokwn/KernelLiveDumpTool/releases/download/v1.1/KernelLiveDumpTool.exe";                                                                                                                                                                                         File="KernelLiveDumpTool.exe" },
    @{ Name="BAM Parser";                  Url="https://github.com/spokwn/BAM-parser/releases/download/v1.2.9/BAMParser.exe";                                                                                                                                                                                                        File="BAMParser.exe" },
    @{ Name="Paths Parser";                Url="https://github.com/spokwn/PathsParser/releases/download/v1.2/PathsParser.exe";                                                                                                                                                                                                       File="PathsParser.exe" },
    @{ Name="JournalTrace";                Url="https://github.com/spokwn/JournalTrace/releases/download/1.2/JournalTrace.exe";                                                                                                                                                                                                      File="JournalTrace.exe" },
    @{ Name="Espouken";                    Url="https://github.com/spokwn/Tool/releases/download/v1.1.3/espouken.exe";                                                                                                                                                                                                               File="espouken.exe" },
    @{ Name="PcaSvc Executed";             Url="https://github.com/spokwn/pcasvc-executed/releases/download/v0.8.7/PcaSvcExecuted.exe";                                                                                                                                                                                              File="PcaSvcExecuted.exe" },
    @{ Name="BAM Deleted Keys";            Url="https://github.com/spokwn/BamDeletedKeys/releases/download/v1.0/BamDeletedKeys.exe";                                                                                                                                                                                                 File="BamDeletedKeys.exe" },
    @{ Name="Prefetch Parser";             Url="https://github.com/spokwn/prefetch-parser/releases/download/v1.5.5/PrefetchParser.exe";                                                                                                                                                                                              File="PrefetchParser.exe" },
    @{ Name="Activities Cache Parser";     Url="https://github.com/spokwn/ActivitiesCache-execution/releases/download/v0.6.5/ActivitiesCacheParser.exe";                                                                                                                                                                             File="ActivitiesCacheParser.exe" },
    @{ Name="AmcacheParser";               Url="https://download.ericzimmermanstools.com/net9/AmcacheParser.zip";                                                                                                                                                                                                                     File="AmcacheParser.zip" },
    @{ Name="AppCompatCacheParser";        Url="https://download.ericzimmermanstools.com/net9/AppCompatCacheParser.zip";                                                                                                                                                                                                              File="AppCompatCacheParser.zip" },
    @{ Name="JumpListExplorer";            Url="https://download.ericzimmermanstools.com/net9/JumpListExplorer.zip";                                                                                                                                                                                                                  File="JumpListExplorer.zip" },
    @{ Name="bstrings";                    Url="https://download.ericzimmermanstools.com/net9/bstrings.zip";                                                                                                                                                                                                                          File="bstrings.zip" },
    @{ Name="PECmd";                       Url="https://download.ericzimmermanstools.com/net9/PECmd.zip";                                                                                                                                                                                                                             File="PECmd.zip" },
    @{ Name="SrumECmd";                    Url="https://download.ericzimmermanstools.com/net9/SrumECmd.zip";                                                                                                                                                                                                                          File="SrumECmd.zip" },
    @{ Name="TimelineExplorer";            Url="https://download.ericzimmermanstools.com/net9/TimelineExplorer.zip";                                                                                                                                                                                                                  File="TimelineExplorer.zip" },
    @{ Name="RegistryExplorer";            Url="https://download.ericzimmermanstools.com/net9/RegistryExplorer.zip";                                                                                                                                                                                                                  File="RegistryExplorer.zip" },
    @{ Name="MFTECmd";                     Url="https://download.ericzimmermanstools.com/net9/MFTECmd.zip";                                                                                                                                                                                                                           File="MFTECmd.zip" },
    @{ Name="WinPrefetchView";             Url="https://www.nirsoft.net/utils/winprefetchview-x64.zip";                                                                                                                                                                                                                               File="winprefetchview-x64.zip" },
    @{ Name="USBDeview";                   Url="https://www.nirsoft.net/utils/usbdeview-x64.zip";                                                                                                                                                                                                                                     File="usbdeview-x64.zip" },
    @{ Name="NetworkUsageView";            Url="https://www.nirsoft.net/utils/networkusageview-x64.zip";                                                                                                                                                                                                                              File="networkusageview-x64.zip" },
    @{ Name="AlternateStreamView";         Url="https://www.nirsoft.net/utils/alternatestreamview-x64.zip";                                                                                                                                                                                                                           File="alternatestreamview-x64.zip" },
    @{ Name="UninstallView";               Url="https://www.nirsoft.net/utils/uninstallview-x64.zip";                                                                                                                                                                                                                                 File="uninstallview-x64.zip" },
    @{ Name="PreviousFilesRecovery";       Url="https://www.nirsoft.net/utils/previousfilesrecovery-x64.zip";                                                                                                                                                                                                                         File="previousfilesrecovery-x64.zip" },
    @{ Name="AltDetector";                 Url="https://github.com/praiselily/AltDetector/releases/download/Detector/AltDetector.exe";                                                                                                                                                                                               File="AltDetector.exe" },
    @{ Name="FakerFinder";                 Url="https://github.com/praiselily/WeHateFakers/releases/download/Screenshare/FakerFinder.jar";                                                                                                                                                                                           File="FakerFinder.jar" },
    @{ Name="HardlinkFinder";              Url="https://github.com/praiselily/HardlinkFinder/releases/download/Tools/hardlink.exe";                                                                                                                                                                                                  File="hardlink.exe" },
    @{ Name="System Informer";             Url="https://github.com/winsiderss/si-builds/releases/download/3.2.25297.1516/systeminformer-build-canary-setup.exe";                                                                                                                                                                     File="systeminformer-build-canary-setup.exe" },
    @{ Name="Everything Search";           Url="https://www.voidtools.com/Everything-1.4.1.1029.x86-Setup.exe";                                                                                                                                                                                                                       File="Everything-1.4.1.1029.x86-Setup.exe" },
    @{ Name="FTK Imager";                  Url="https://www.mediafire.com/file/qqhbjhop1zgufsa/Exterro_FTK_Imager_%28x64%29-4.7.3.81.exe/file";                                                                                                                                                                                     File="Exterro_FTK_Imager_x64-4.7.3.81.exe" },
    @{ Name="InjGen";                      Url="https://github.com/NotRequiem/InjGen/releases/download/v2.0/InjGen.exe";                                                                                                                                                                                                             File="InjGen.exe" },
    @{ Name="PrefetchView++";              Url="https://github.com/Orbdiff/PrefetchView/releases/download/v1.5.4/PrefetchView++.exe";                                                                                                                                                                                                File="PrefetchView++.exe" },
    @{ Name="Velociraptor";                Url="https://github.com/Velocidex/velociraptor/releases/download/v0.6.6-1/velociraptor-v0.6.6-3-windows-386.exe";                                                                                                                                                                        File="velociraptor-v0.6.6-3-windows-386.exe" },
    @{ Name="Recaf";                       Url="https://github.com/Col-E/Recaf/releases/download/4.0.0-alpha/recaf-4x-alpha-win-86x64.jar";                                                                                                                                                                                         File="recaf-4x-alpha-win-86x64.jar" },
    @{ Name="Magnet RESPONSE";             Url="https://download1523.mediafire.com/gk67r6nckolg0pVDmP5hLkBI3VjM7Af0YDg8r64Ud95cg71fsgx30IIZdel2UnxZwffrJGajQqcaacuX92JTv2k9t0QhD0Q4QoMj_6KwY048nunCaPizYhnz2kjBXikuFd3nZcnceD2SJMOUOwJATJ-zBD7RIK-eXpcSI8L1JMUYXA/lxnu4z9sqzz63lc/MRCv120.exe";                          File="MRCv120.exe" },
    @{ Name="Hayabusa";                    Url="https://github.com/Yamato-Security/hayabusa/releases/download/v3.6.0/hayabusa-3.6.0-win-x64.zip";                                                                                                                                                                                   File="hayabusa-3.6.0-win-x64.zip" }
)

Add-DefenderExclusion

Write-Divider "DOWNLOAD"
Write-Host ""

$confirm = Read-Host "  Download all $($allTools.Count) tools? (Y/N)"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "  Cancelled." -ForegroundColor $neutral
    exit
}

$dotnet = Read-Host "  Install .NET Runtime? Required for Zimmerman tools (Y/N)"

Write-Host ""

$i = 0
foreach ($tool in $allTools) {
    $i++
    Download-File -Url $tool.Url -FileName $tool.File -ToolName $tool.Name -Index $i -Total $allTools.Count
}

if ($dotnet -match '^[Yy]') {
    $i++
    Download-File -Url "https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.306/dotnet-sdk-9.0.306-win-x64.exe" -FileName "dotnet-sdk-9.0.306-win-x64.exe" -ToolName ".NET Runtime" -Index $i -Total ($allTools.Count + 1)
}

Write-Divider "COMPLETE"
Write-Summary -Downloaded $script:totalDownloaded -Total $allTools.Count -Path $DownloadPath
Write-Host ""
