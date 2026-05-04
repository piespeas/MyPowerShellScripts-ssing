# ============================================================
#   AcousticVoid Suite
#   1. System Checker
#   2. Void Mod Analyzer
#   3. Command History Analyzer
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# -------------------------------------------------------------
#  ADMIN CHECK  (shared - only need it once)
# -------------------------------------------------------------
$isAdmin = [System.Security.Principal.WindowsPrincipal]::new(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n" -ForegroundColor Red
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host "        ADMINISTRATOR PRIVILEGES REQUIRED       " -ForegroundColor Red
    Write-Host "      Please run this script as Administrator!    " -ForegroundColor Red
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host "`n" -ForegroundColor Red
    exit
}


# ============================================================
#  PART 1 - SYSTEM CHECKER
# ============================================================
# verdict tracking - collected across both parts, evaluated at the very end
$verdictFlags    = [System.Collections.Generic.List[string]]::new()
$verdictWarnings = [System.Collections.Generic.List[string]]::new()

Clear-Host
Write-Host "by AcousticVoid" -ForegroundColor Cyan
Write-Host ""

# -- Boot time ------------------------------------------------
try {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime   = (Get-Date) - $bootTime
    Write-Host "SYSTEM BOOT TIME" -ForegroundColor Cyan
    Write-Host ("  Last Boot: {0}" -f $bootTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("  Uptime: {0} days, {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor White
} catch {
    Write-Host "Unable to retrieve boot time information" -ForegroundColor Red
}

try {
    $mcProc = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $mcProc) { $mcProc = Get-Process java -ErrorAction SilentlyContinue }
    if ($mcProc) {
        $mcUptime = (Get-Date) - $mcProc.StartTime
        Write-Host ("  Minecraft Start: {0}" -f $mcProc.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
        Write-Host ("  MC Uptime: {0} days, {1:D2}:{2:D2}:{3:D2}" -f $mcUptime.Days, $mcUptime.Hours, $mcUptime.Minutes, $mcUptime.Seconds) -ForegroundColor White
    } else {
        Write-Host "  Minecraft: Not running" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Unable to retrieve Minecraft process info" -ForegroundColor Red
}

# -- Connected drives -------------------------------------------
$drives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    Write-Host "`nCONNECTED DRIVES" -ForegroundColor Cyan
    foreach ($drive in $drives) {
        Write-Host ("  {0}: {1}" -f $drive.DeviceID, $drive.FileSystem) -ForegroundColor White
    }
}

# -- Services --------------------------------------------------
Write-Host "`nSERVICE STATUS" -ForegroundColor Cyan

$services = @(
    @{Name = "SysMain";    DisplayName = "SysMain"},
    @{Name = "PcaSvc";     DisplayName = "Program Compatibility Assistant Service"},
    @{Name = "DPS";        DisplayName = "Diagnostic Policy Service"},
    @{Name = "EventLog";   DisplayName = "Windows Event Log"},
    @{Name = "Schedule";   DisplayName = "Task Scheduler"},
    @{Name = "Bam";        DisplayName = "Background Activity Moderator"},
    @{Name = "Dusmsvc";    DisplayName = "Data Usage"},
    @{Name = "Appinfo";    DisplayName = "Application Information"},
    @{Name = "CDPSvc";     DisplayName = "Connected Devices Platform Service"},
    @{Name = "DcomLaunch"; DisplayName = "DCOM Server Process Launcher"},
    @{Name = "PlugPlay";   DisplayName = "Plug and Play"},
    @{Name = "wsearch";    DisplayName = "Windows Search"}
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) { $displayName = $displayName.Substring(0, 37) + "..." }
            Write-Host ("  {0,-25} {1}" -f $svc.DisplayName, $service.Status) -ForegroundColor Magenta -NoNewline

            if ($svc.Name -eq "Bam") {
                Write-Host " | Enabled" -ForegroundColor Yellow
            } else {
                try {
                    $process = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object ProcessId
                    if ($process.ProcessId -gt 0) {
                        $proc = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                        if ($proc) { Write-Host (" | {0}" -f $proc.StartTime.ToString("HH:mm:ss")) -ForegroundColor Yellow }
                        else       { Write-Host " | N/A" -ForegroundColor Yellow }
                    } else {
                        Write-Host " | N/A" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host " | N/A" -ForegroundColor Yellow
                }
            }
        } else {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) { $displayName = $displayName.Substring(0, 37) + "..." }
            Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, $displayName, $service.Status) -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, "Not Found", "Stopped") -ForegroundColor Gray
    }
}

# -- Registry --------------------------------------------------
Write-Host "`nREGISTRY" -ForegroundColor Magenta

$regSettings = @(
    @{ Name = "CMD";               Path = "HKCU:\Software\Policies\Microsoft\Windows\System";                               Key = "DisableCMD";                Warning = "Disabled"; Safe = "Available" },
    @{ Name = "PowerShell Logging";Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging";        Key = "EnableScriptBlockLogging";  Warning = "Disabled"; Safe = "Enabled" },
    @{ Name = "Activities Cache";  Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                               Key = "EnableActivityFeed";        Warning = "Disabled"; Safe = "Enabled" },
    @{ Name = "Prefetch Enabled";  Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key = "EnablePrefetcher"; Warning = "Disabled"; Safe = "Enabled" }
)

foreach ($s in $regSettings) {
    $status = Get-ItemProperty -Path $s.Path -Name $s.Key -ErrorAction SilentlyContinue
    Write-Host "  " -NoNewline
    if ($status -and $status.$($s.Key) -eq 0) {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host "$($s.Warning)" -ForegroundColor Red
    } else {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host "$($s.Safe)" -ForegroundColor Magenta
    }
}

# -- USB history -----------------------------------------------
Write-Host "`nUSB HISTORY" -ForegroundColor Magenta
try {
    $usbRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
    if (Test-Path $usbRegPath) {
        $usbDevices = Get-ChildItem -Path $usbRegPath -ErrorAction SilentlyContinue
        if ($usbDevices) {
            foreach ($device in $usbDevices) {
                $instances = Get-ChildItem -Path $device.PSPath -ErrorAction SilentlyContinue
                foreach ($instance in $instances) {
                    $props        = Get-ItemProperty -Path $instance.PSPath -ErrorAction SilentlyContinue
                    $friendlyName = $props.FriendlyName
                    if (-not $friendlyName) { $friendlyName = $device.PSChildName -replace "_", " " }

                    # last plug-in time from the Properties subkey
                    $lastArrival = $null
                    $propKey = Join-Path $instance.PSPath "Properties\{83da6326-97a6-4088-9453-a1923f573b29}\0065"
                    if (Test-Path $propKey) {
                        $raw = Get-ItemProperty -Path $propKey -ErrorAction SilentlyContinue
                        if ($raw.'(default)') {
                            try { $lastArrival = [datetime]::FromFileTime([BitConverter]::ToInt64($raw.'(default)', 0)) } catch {}
                        }
                    }

                    Write-Host "  * " -NoNewline -ForegroundColor Magenta
                    Write-Host $friendlyName -ForegroundColor White -NoNewline
                    if ($lastArrival) {
                        Write-Host (" | Last seen: {0}" -f $lastArrival.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
                    } else {
                        Write-Host ""
                    }
                    
                    # Add time stamps for USB devices
                    $deviceProps = Get-WmiObject -Class Win32_USBControllerDevice -Filter "DeviceID='$($device.DeviceID)'" -ErrorAction SilentlyContinue
                    if ($deviceProps) {
                        Write-Host "    | Connected: $($deviceProps.Connected)" -ForegroundColor Gray
                        Write-Host "    | Driver Date: $($deviceProps.DriverDate)" -ForegroundColor Gray
                        Write-Host "    | Driver Version: $($deviceProps.DriverVersion)" -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Host "  No USB storage devices found in registry" -ForegroundColor Magenta
        }
    } else {
        Write-Host "  USBSTOR registry key not accessible" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Error reading USB history: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Active USB Devices --------------------------------------
Write-Host "`nACTIVE USB DEVICES" -ForegroundColor Magenta
try {
    $activeDevices = Get-WmiObject -Class Win32_USBControllerDevice -ErrorAction SilentlyContinue
    if ($activeDevices) {
        Write-Host "  Connected USB devices:" -ForegroundColor White
        foreach ($device in $activeDevices) {
            $deviceInfo = ""
            if ($device.DeviceID) { $deviceInfo += "ID: $($device.DeviceID) " }
            if ($device.Description) { $deviceInfo += "Desc: $($device.Description) " }
            if ($device.Manufacturer) { $deviceInfo += "Mfg: $($device.Manufacturer) " }
            if ($device.PNPDeviceID) { $deviceInfo += "PNP: $($device.PNPDeviceID)" }
            
            Write-Host "  * $($device.Name)" -ForegroundColor Cyan -NoNewline
            Write-Host "    $deviceInfo" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No active USB devices found" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Error enumerating USB devices: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Logged-on users -------------------------------------------
Write-Host "`nLOGGED-ON USERS" -ForegroundColor Magenta
try {
    # Get interactive sessions (console/logged in users)
    $sessions = query user
    if ($sessions) {
        Write-Host "  Interactive sessions:" -ForegroundColor White
        foreach ($session in $sessions) {
            $sessionInfo = ""
            $sessionInfo += "User: $($session.UserName) "
            $sessionInfo += "Domain: $($session.DomainName) "
            $sessionInfo += "State: $($session.State) "
            $sessionInfo += "Logon Time: $($session.LogonTime.ToString('yyyy-MM-dd HH:mm:ss')) "
            $sessionInfo += "Idle Time: $([math]::Round((Get-Date) - $session.LogonTime).TotalMinutes, 0))m"
            
            Write-Host "  * $($session.UserName)" -ForegroundColor Cyan -NoNewline
            Write-Host "    $sessionInfo" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No interactive sessions found" -ForegroundColor Gray
    }
    
    # Get all logged-on users (including services)
    $loggedOnUsers = Get-WmiObject -Class Win32_LoggedOnUser -ErrorAction SilentlyContinue
    if ($loggedOnUsers) {
        Write-Host "  All logged-on users:" -ForegroundColor White
        foreach ($user in $loggedOnUsers) {
            $userInfo = ""
            $userInfo += "User: $($user.UserName) "
            $userInfo += "Domain: $($user.Domain) "
            $userInfo += "Logon Type: $($user.LogonType) "
            $userInfo += "Start Time: $($user.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            
            Write-Host "  * $($user.UserName)" -ForegroundColor Yellow -NoNewline
            Write-Host "    $userInfo" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No logged-on users found via WMI" -ForegroundColor Gray
    }
    
    # Get current user session details
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "  Current script user: $currentUser" -ForegroundColor Green
    
} catch {
    Write-Host "  Error enumerating logged-on users: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Event log helpers -----------------------------------------
function Check-EventLog {
    param ($logName, $eventID, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$eventID]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Magenta
    }
}

function Check-RecentEventLog {
    param ($logName, $eventIDs, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$($eventIDs -join ' or EventID=')]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message (ID: $($event.Id)) at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Magenta
    }
}

function Check-DeviceDeleted {
    try {
        $event = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) { Write-Host "  Device configuration changed at: " -NoNewline -ForegroundColor White; Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow; return }
    } catch {}
    try {
        $event = Get-WinEvent -FilterHashtable @{LogName="System"; ID=225} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) { Write-Host "  Device removed at: " -NoNewline -ForegroundColor White; Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow; return }
    } catch {}
    try {
        $events = Get-WinEvent -LogName "System" | Where-Object {$_.Id -eq 225 -or $_.Id -eq 400} | Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($events) { Write-Host "  Last device change at: " -NoNewline -ForegroundColor White; Write-Host $events.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow; return }
    } catch {}
    Write-Host "  Device changes - No records found" -ForegroundColor Magenta
}

# -- Event logs ------------------------------------------------
Write-Host "`nEVENT LOGS" -ForegroundColor Magenta
Check-EventLog      "Application" 3079          "USN Journal cleared"
Check-RecentEventLog "System"     @(104, 1102)  "Event Logs cleared"
Check-EventLog      "System"      1074           "Last PC Shutdown"
Check-EventLog      "Security"    4616           "System time changed"
Check-EventLog      "System"      6005           "Event Log Service started"
Check-DeviceDeleted

# -- Comprehensive Event ID Parsing --------------------------------
Write-Host "`nCOMPREHENSIVE EVENT ID ANALYSIS" -ForegroundColor Cyan
try {
    # Define suspicious event IDs by category
    $suspiciousEvents = @{
        Security = @(
            @{ID = 4624; Desc = "Account logon - success"; Category = "Authentication"},
            @{ID = 4625; Desc = "Account logon - failed"; Category = "Authentication"},
            @{ID = 4634; Desc = "Account logoff"; Category = "Authentication"},
            @{ID = 4648; Desc = "Explicit credentials used"; Category = "Authentication"},
            @{ID = 4720; Desc = "User account created"; Category = "Account Management"},
            @{ID = 4722; Desc = "User account enabled"; Category = "Account Management"},
            @{ID = 4723; Desc = "User account password changed"; Category = "Account Management"},
            @{ID = 4724; Desc = "User account deleted"; Category = "Account Management"},
            @{ID = 4725; Desc = "User account disabled"; Category = "Account Management"},
            @{ID = 4732; Desc = "Member added to security group"; Category = "Account Management"},
            @{ID = 4733; Desc = "Member removed from security group"; Category = "Account Management"},
            @{ID = 4768; Desc = "Kerberos TGT requested"; Category = "Authentication"},
            @{ID = 4769; Desc = "Kerberos TGT failed"; Category = "Authentication"},
            @{ID = 4770; Desc = "Kerberos service ticket requested"; Category = "Authentication"},
            @{ID = 4771; Desc = "Kerberos service ticket failed"; Category = "Authentication"},
            @{ID = 4776; Desc = "Computer account authentication"; Category = "Authentication"},
            @{ID = 4778; Desc = "Account locked out"; Category = "Authentication"},
            @{ID = 4779; Desc = "Account unlocked"; Category = "Authentication"},
            @{ID = 4946; Desc = "New firewall rule added"; Category = "Security Policy"},
            @{ID = 4947; Desc = "Firewall rule modified"; Category = "Security Policy"},
            @{ID = 4948; Desc = "Firewall rule deleted"; Category = "Security Policy"},
            @{ID = 4657; Desc = "Registry value modified"; Category = "Object Access"},
            @{ID = 4663; Desc = "Object access attempt"; Category = "Object Access"},
            @{ID = 4670; Desc = "Permissions on object changed"; Category = "Object Access"},
            @{ID = 4688; Desc = "Process created"; Category = "Process Tracking"},
            @{ID = 4689; Desc = "Process terminated"; Category = "Process Tracking"},
            @{ID = 4696; Desc = "Primary token assigned"; Category = "Process Tracking"},
            @{ID = 4697; Desc = "Primary token assigned to process"; Category = "Process Tracking"},
            @{ID = 4698; Desc = "Special privileges assigned"; Category = "Process Tracking"},
            @{ID = 4702; Desc = "Special privileges assigned to new logon"; Category = "Process Tracking"},
            @{ID = 4719; Desc = "System audit policy changed"; Category = "Policy Change"},
            @{ID = 4715; Desc = "The Windows Filtering Platform has blocked a packet"; Category = "Network"},
            @{ID = 5156; Desc = "Windows Filtering Platform blocked connection"; Category = "Network"},
            @{ID = 5157; Desc = "Windows Filtering Platform blocked connection"; Category = "Network"},
            @{ID = 5158; Desc = "Windows Filtering Platform allowed connection"; Category = "Network"},
            @{ID = 5025; Desc = "Windows Firewall Service stopped"; Category = "Security Policy"},
            @{ID = 5033; Desc = "Windows Firewall Service started"; Category = "Security Policy"}
        )
        System = @(
            @{ID = 41; Desc = "System rebooted without clean shutdown"; Category = "System"},
            @{ID = 42; Desc = "System power failure"; Category = "Hardware"},
            @{ID = 100; Desc = "Hard drive error"; Category = "Hardware"},
            @{ID = 101; Desc = "Hard drive error"; Category = "Hardware"},
            @{ID = 104; Desc = "Event log cleared"; Category = "Log Management"},
            @{ID = 1102; Desc = "Audit log cleared"; Category = "Log Management"},
            @{ID = 6005; Desc = "Event log service started"; Category = "Service"},
            @{ID = 6006; Desc = "Event log service stopped"; Category = "Service"},
            @{ID = 6008; Desc = "Previous system shutdown was unexpected"; Category = "System"},
            @{ID = 6009; Desc = "Microsoft (R) Windows (R) version info"; Category = "System"},
            @{ID = 6013; Desc = "Microsoft (R) Windows (R) version info"; Category = "System"},
            @{ID = 7031; Desc = "Service terminated unexpectedly"; Category = "Service"},
            @{ID = 7034; Desc = "Service terminated unexpectedly"; Category = "Service"},
            @{ID = 7036; Desc = "Service entered running state"; Category = "Service"},
            @{ID = 7040; Desc = "Service start type changed"; Category = "Service"},
            @{ID = 7045; Desc = "New service installed"; Category = "Service"},
            @{ID = 20001; Desc = "Scheduled task started"; Category = "Task Scheduler"},
            @{ID = 20002; Desc = "Scheduled task action started"; Category = "Task Scheduler"},
            @{ID = 20003; Desc = "Scheduled task completed"; Category = "Task Scheduler"},
            @{ID = 20004; Desc = "Scheduled task failed"; Category = "Task Scheduler"},
            @{ID = 20012; Desc = "Scheduled task registered"; Category = "Task Scheduler"},
            @{ID = 20013; Desc = "Scheduled task deleted"; Category = "Task Scheduler"},
            @{ID = 7000; Desc = "Service failed to start"; Category = "Service"},
            @{ID = 7001; Desc = "Service hung on starting"; Category = "Service"},
            @{ID = 7002; Desc = "Service hung on stopping"; Category = "Service"},
            @{ID = 7009; Desc = "Service hung on starting"; Category = "Service"}
        )
        Application = @(
            @{ID = 1000; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1001; Desc = "Application fault bucket"; Category = "Application Crash"},
            @{ID = 1002; Desc = "Application hang"; Category = "Application Crash"},
            @{ID = 1003; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1004; Desc = "Windows Explorer has restarted"; Category = "Application Crash"},
            @{ID = 1005; Desc = "Windows Explorer failed to start"; Category = "Application Crash"},
            @{ID = 1008; Desc = "Per-session services failed"; Category = "Service"},
            @{ID = 1010; Desc = "Event processing failed"; Category = "Service"},
            @{ID = 1020; Desc = "Windows could not start service"; Category = "Service"},
            @{ID = 1024; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1026; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1028; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1030; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1033; Desc = "Application error"; Category = "Application Crash"},
            @{ID = 1101; Desc = "Audit events have been dropped"; Category = "Security"},
            @{ID = 1114; Desc = "Software restriction policy rule applied"; Category = "Security"},
            @{ID = 1116; Desc = "Software restriction policy rule applied"; Category = "Security"},
            @{ID = 3079; Desc = "USN Journal cleared"; Category = "File System"},
            @{ID = 5058; Desc = "Windows File Protection"; Category = "File System"},
            @{ID = 5059; Desc = "Windows File Protection"; Category = "File System"},
            @{ID = 5586; Desc = "Windows File Protection"; Category = "File System"}
        )
        Microsoft_Windows_Sysmon_Operational = @(
            @{ID = 1; Desc = "Process created"; Category = "Process"},
            @{ID = 2; Desc = "Process changed file time"; Category = "File System"},
            @{ID = 3; Desc = "Network connection"; Category = "Network"},
            @{ID = 4; Desc = "Sysmon service state changed"; Category = "Service"},
            @{ID = 5; Desc = "Process terminated"; Category = "Process"},
            @{ID = 6; Desc = "Driver loaded"; Category = "Driver"},
            @{ID = 7; Desc = "Image loaded"; Category = "Process"},
            @{ID = 8; Desc = "CreateRemoteThread"; Category = "Process"},
            @{ID = 9; Desc = "RawAccessRead"; Category = "File System"},
            @{ID = 10; Desc = "ProcessAccess"; Category = "Process"},
            @{ID = 11; Desc = "FileCreate"; Category = "File System"},
            @{ID = 12; Desc = "Registry object added or deleted"; Category = "Registry"},
            @{ID = 13; Desc = "Registry value set"; Category = "Registry"},
            @{ID = 14; Desc = "Registry key renamed"; Category = "Registry"},
            @{ID = 15; Desc = "FileCreateStreamHash"; Category = "File System"},
            @{ID = 16; Desc = "Sysmon config change"; Category = "Configuration"},
            @{ID = 17; Desc = "PipeEvent"; Category = "IPC"},
            @{ID = 18; Desc = "WmiEvent"; Category = "WMI"},
            @{ID = 19; Desc = "WmiEventConsumer"; Category = "WMI"},
            @{ID = 20; Desc = "WmiEventConsumerToFilter"; Category = "WMI"},
            @{ID = 21; Desc = "WmiEventFilter"; Category = "WMI"},
            @{ID = 22; Desc = "DNSEvent"; Category = "Network"},
            @{ID = 23; Desc = "FileDelete"; Category = "File System"},
            @{ID = 24; Desc = "ClipboardChange"; Category = "Process"},
            @{ID = 25; Desc = "ProcessTampering"; Category = "Process"},
            @{ID = 26; Desc = "ImageLoad"; Category = "Process"},
            @{ID = 27; Desc = "FileDeleteDetected"; Category = "File System"},
            @{ID = 28; Desc = "FileExecutableDetected"; Category = "File System"}
        )
    }

    # Function to analyze events for a specific log
    function Analyze-EventLog {
        param($logName, $eventDefinitions, $hoursBack = 24)
        
        $startTime = (Get-Date).AddHours(-$hoursBack)
        $foundEvents = @()
        
        Write-Host "`n  Analyzing $logName (last $hoursBack hours)" -ForegroundColor White
        
        try {
            $allEventIDs = $eventDefinitions | ForEach-Object { $_.ID }
            $idString = $allEventIDs -join " or EventID="
            
            $events = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$idString] and TimeCreated[@SystemTime>='$($startTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))']]]" -ErrorAction SilentlyContinue
            
            if ($events) {
                foreach ($event in $events) {
                    $eventDef = $eventDefinitions | Where-Object { $_.ID -eq $event.Id }
                    if ($eventDef) {
                        $foundEvents += [PSCustomObject]@{
                            ID = $event.Id
                            Description = $eventDef.Desc
                            Category = $eventDef.Category
                            TimeCreated = $event.TimeCreated
                            Message = ($event.Message -split "`n")[0] # First line only
                        }
                    }
                }
            }
        } catch {
            Write-Host "    Error accessing $logName`: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        return $foundEvents
    }

    # Analyze each log type
    $allSuspiciousEvents = @()
    
    # Check if logs exist before analyzing
    $availableLogs = Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } | Select-Object -ExpandProperty LogName
    
    # Analyze Security log
    if ("Security" -in $availableLogs) {
        $securityEvents = Analyze-EventLog "Security" $suspiciousEvents.Security
        $allSuspiciousEvents += $securityEvents
    }
    
    # Analyze System log
    if ("System" -in $availableLogs) {
        $systemEvents = Analyze-EventLog "System" $suspiciousEvents.System
        $allSuspiciousEvents += $systemEvents
    }
    
    # Analyze Application log
    if ("Application" -in $availableLogs) {
        $appEvents = Analyze-EventLog "Application" $suspiciousEvents.Application
        $allSuspiciousEvents += $appEvents
    }
    
    # Analyze Sysmon log (if available)
    if ("Microsoft-Windows-Sysmon/Operational" -in $availableLogs) {
        $sysmonEvents = Analyze-EventLog "Microsoft-Windows-Sysmon/Operational" $suspiciousEvents.Microsoft_Windows_Sysmon_Operational
        $allSuspiciousEvents += $sysmonEvents
    }
    
    # Display results by category
    if ($allSuspiciousEvents.Count -gt 0) {
        Write-Host "`n  SUSPICIOUS EVENTS FOUND: $($allSuspiciousEvents.Count)" -ForegroundColor Red
        
        # Group by category
        $groupedEvents = $allSuspiciousEvents | Group-Object Category | Sort-Object Name
        
        foreach ($group in $groupedEvents) {
            Write-Host "`n    $($group.Name.ToUpper()) ($($group.Count) events):" -ForegroundColor Yellow
            
            # Sort by time (newest first) and limit to 10 per category to avoid spam
            $categoryEvents = $group.Group | Sort-Object TimeCreated -Descending | Select-Object -First 10
            
            foreach ($event in $categoryEvents) {
                $timeStr = $event.TimeCreated.ToString("MM/dd HH:mm")
                Write-Host "      [$($event.ID)] $timeStr - $($event.Description)" -ForegroundColor White
                if ($event.Message -and $event.Message.Length -lt 100) {
                    Write-Host "        $($event.Message)" -ForegroundColor Gray
                }
            }
            
            if ($group.Group.Count -gt 10) {
                Write-Host "        ... and $($group.Group.Count - 10) more events" -ForegroundColor Gray
            }
        }
        
        # Time correlation analysis
        $recentEvents = $allSuspiciousEvents | Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-2) }
        if ($recentEvents.Count -gt 5) {
            Write-Host "`n    HIGH ACTIVITY DETECTED: $($recentEvents.Count) events in last 2 hours" -ForegroundColor Red
            $verdictFlags.Add("High event activity in last 2 hours")
        }
        
    } else {
        Write-Host "`n  No suspicious events found in the last 24 hours" -ForegroundColor Green
    }
    
    # Quick summary of most critical event types
    Write-Host "`n  CRITICAL EVENT SUMMARY (Last 24h):" -ForegroundColor Magenta
    
    $criticalIDs = @(4625, 4720, 4724, 4732, 4657, 4688, 41, 104, 1102, 1000, 1002)
    $criticalEvents = $allSuspiciousEvents | Where-Object { $_.ID -in $criticalIDs }
    
    if ($criticalEvents) {
        foreach ($event in $criticalEvents | Sort-Object TimeCreated -Descending) {
            $timeStr = $event.TimeCreated.ToString("MM/dd HH:mm")
            $color = switch ($event.ID) {
                {$_ -in @(104, 1102)} { "Red" }  # Log clearing
                {$_ -in @(4625, 4724)} { "Red" }  # Failed logins, account deletion
                {$_ -in @(4720, 4732)} { "Yellow" } # Account creation, group changes
                {$_ -in @(4657, 4688)} { "Yellow" } # Registry changes, process creation
                {$_ -in @(41, 1000, 1002)} { "Yellow" } # System crashes, app errors
                default { "White" }
            }
            Write-Host "    [$($event.ID)] $timeStr - $($event.Description)" -ForegroundColor $color
        }
    } else {
        Write-Host "    No critical security events detected" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  Error during comprehensive event analysis: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Prefetch integrity ----------------------------------------
$prefetchPath = "$env:SystemRoot\Prefetch"
if (Test-Path $prefetchPath) {
    Write-Host "`nPREFETCH INTEGRITY" -ForegroundColor Magenta

    $files = Get-ChildItem -Path $prefetchPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  No prefetch found?? Check the folder please" -ForegroundColor Yellow
    } else {
        $hashTable              = @{}
        $suspiciousFiles        = @{}
        $totalFiles             = $files.Count
        $hiddenFiles            = @()
        $readOnlyFiles          = @()
        $hiddenAndReadOnlyFiles = @()

        foreach ($file in $files) {
            try {
                $isHidden   = $file.Attributes -band [System.IO.FileAttributes]::Hidden
                $isReadOnly = $file.Attributes -band [System.IO.FileAttributes]::ReadOnly

                if ($isHidden -and $isReadOnly) {
                    $hiddenAndReadOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) { $suspiciousFiles[$file.Name] = "Hidden and Read-only" }
                } elseif ($isHidden) {
                    $hiddenFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) { $suspiciousFiles[$file.Name] = "Hidden file" }
                } elseif ($isReadOnly) {
                    $readOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) { $suspiciousFiles[$file.Name] = "Read-only file" }
                }

                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($hash) {
                    if ($hashTable.ContainsKey($hash.Hash)) { $hashTable[$hash.Hash].Add($file.Name) }
                    else { $hashTable[$hash.Hash] = [System.Collections.Generic.List[string]]::new(); $hashTable[$hash.Hash].Add($file.Name) }
                }
            } catch {
                if (-not $suspiciousFiles.ContainsKey($file.Name)) { $suspiciousFiles[$file.Name] = "Error analyzing file: $($_.Exception.Message)" }
            }
        }

        if ($hiddenAndReadOnlyFiles.Count -gt 0) {
            Write-Host "  Hidden & Read-only Files: $($hiddenAndReadOnlyFiles.Count) found" -ForegroundColor Yellow
            foreach ($file in $hiddenAndReadOnlyFiles) { Write-Host ("    {0}" -f $file.Name) -ForegroundColor White }
        }

        if ($hiddenFiles.Count -gt 0) {
            Write-Host "  Hidden Files: $($hiddenFiles.Count) found" -ForegroundColor Yellow
            foreach ($file in $hiddenFiles) { Write-Host ("    {0}" -f $file.Name) -ForegroundColor White }
        } else { Write-Host "  Hidden Files: None" -ForegroundColor Magenta }

        if ($readOnlyFiles.Count -gt 0) {
            Write-Host "  Read-Only Files: $($readOnlyFiles.Count)" -ForegroundColor Yellow
            foreach ($file in $readOnlyFiles) { Write-Host ("    {0}" -f $file.Name) -ForegroundColor White }
        } else { Write-Host "  Read-Only Files: None" -ForegroundColor Magenta }

        $repeatedHashes = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($repeatedHashes) {
            Write-Host "  Duplicate Files: $($repeatedHashes.Count) sets found" -ForegroundColor Yellow
            foreach ($entry in $repeatedHashes) {
                foreach ($f in $entry.Value) { if (-not $suspiciousFiles.ContainsKey($f)) { $suspiciousFiles[$f] = "Duplicate file" } }
                Write-Host ("    Duplicate set: {0}" -f ($entry.Value -join ", ")) -ForegroundColor White
            }
        } else { Write-Host "  Duplicates: None" -ForegroundColor Magenta }

        if ($suspiciousFiles.Count -gt 0) {
            Write-Host "`n  SUSPICIOUS FILES FOUND: $($suspiciousFiles.Count)/$totalFiles" -ForegroundColor Yellow
            foreach ($entry in $suspiciousFiles.GetEnumerator() | Sort-Object Key) {
                Write-Host ("    {0} : {1}" -f $entry.Key, $entry.Value) -ForegroundColor White
            }
        } else {
            Write-Host "`n  Prefetch integrity: Clean ($totalFiles files checked)" -ForegroundColor Magenta
        }
    }
} else {
    Write-Host "`nCouldnt find prefetch folder?? (check yo paths hoe)" -ForegroundColor Red
}

# -- Late JAR injection into javaw.exe -------------------------
Write-Host "`nLATE JAR INJECTION CHECK" -ForegroundColor Cyan
try {
    $mcProc = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $mcProc) { $mcProc = Get-Process java -ErrorAction SilentlyContinue }

    if (-not $mcProc) {
        Write-Host "  Minecraft (javaw/java) is not running" -ForegroundColor Gray
    } else {
        $procStartTime   = $mcProc.StartTime
        $injectionWindow = $procStartTime.AddMinutes(2)
        $suspiciousJars  = [System.Collections.Generic.List[object]]::new()
        $allJars2        = [System.Collections.Generic.List[object]]::new()

        $modsRoot = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
        if (Test-Path $modsRoot) {
            $jarFiles2 = Get-ChildItem -Path $modsRoot -Filter *.jar -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($jar in $jarFiles2) {
                $allJars2.Add($jar)
                # LastAccessTime updates when the JVM reads the file into its classloader
                if ($jar.LastAccessTime -gt $injectionWindow) {
                    $suspiciousJars.Add($jar)
                }
            }
        }

        Write-Host ("  Minecraft started:  {0}" -f $procStartTime.ToString("HH:mm:ss"))                         -ForegroundColor White
        Write-Host ("  Suspicious after:   {0}  (+2 min grace period)" -f $injectionWindow.ToString("HH:mm:ss")) -ForegroundColor Gray
        Write-Host ("  JARs in mods folder: {0}" -f $allJars2.Count)                                            -ForegroundColor White

        if ($suspiciousJars.Count -eq 0) {
            Write-Host "  No late-loaded JARs detected" -ForegroundColor Magenta
        } else {
            Write-Host ("  LATE-LOADED JARs DETECTED: {0}" -f $suspiciousJars.Count) -ForegroundColor Red
            Write-Host "  Used to check for stuff like replaces (check timestamps)" -ForegroundColor Gray
            foreach ($jar in ($suspiciousJars | Sort-Object LastAccessTime -Descending)) {
                Write-Host "    ! " -NoNewline -ForegroundColor Red
                Write-Host $jar.Name -NoNewline -ForegroundColor Yellow
                Write-Host (" | Accessed: {0}" -f $jar.LastAccessTime.ToString("HH:mm:ss")) -ForegroundColor White
            }
        }
    }
} catch {
    Write-Host "  Error during injection check: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Windows Defender real-time protection --------------------
Write-Host "`nWINDOWS DEFENDER" -ForegroundColor Magenta
try {
    $defenderKey  = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    $defenderPol  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"

    $rtpValue     = (Get-ItemProperty -Path $defenderKey  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
    $polValue     = (Get-ItemProperty -Path $defenderPol  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
    $tamperValue  = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -ErrorAction SilentlyContinue).TamperProtection

    $rtpDisabled  = ($rtpValue -eq 1) -or ($polValue -eq 1)

    Write-Host "  Real-Time Protection: " -NoNewline -ForegroundColor White
    if ($rtpDisabled) {
        Write-Host "DISABLED" -ForegroundColor Red
    } else {
        Write-Host "Enabled" -ForegroundColor Magenta
    }

    Write-Host "  Tamper Protection:    " -NoNewline -ForegroundColor White
    if ($tamperValue -eq 5) {
        Write-Host "Enabled" -ForegroundColor Magenta
    } elseif ($null -eq $tamperValue) {
        Write-Host "Unknown" -ForegroundColor Gray
    } else {
        Write-Host "DISABLED" -ForegroundColor Red
    }

    if ($polValue -eq 1) {
        Write-Host "  Note: Disabled via Group Policy" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Error reading Defender status: $($_.Exception.Message)" -ForegroundColor Red
}

# -- JVM Checker (PART 4) -----------------------------------
Write-Host "`nJVM CHECKER" -ForegroundColor Magenta
try {
    $mcProc = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $mcProc) { $mcProc = Get-Process java -ErrorAction SilentlyContinue }

    if (-not $mcProc) {
        Write-Host "  Minecraft is not running" -ForegroundColor Gray
    } else {
        # Get JVM information from the process
        $processId = $mcProc.Id
        
        # Get command line arguments
        $commandLine = (Get-WmiObject -Class Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue).CommandLine
        if ($commandLine) {
            Write-Host "  Command Line:" -ForegroundColor White
            Write-Host "    $commandLine" -ForegroundColor Gray
            
            # Extract JVM arguments
            $jvmArgs = @()
            $args = $commandLine -split ' '
            foreach ($arg in $args) {
                if ($arg -like '-D*' -or $arg -like '-X*' -or $arg -like '-XX*') {
                    $jvmArgs += $arg
                }
            }
            
            if ($jvmArgs.Count -gt 0) {
                Write-Host "  JVM Arguments:" -ForegroundColor Yellow
                foreach ($arg in $jvmArgs) {
                    Write-Host "    $arg" -ForegroundColor White
                }
            } else {
                Write-Host "  No JVM arguments detected" -ForegroundColor Green
            }
            
            # Check for suspicious JVM flags
            $suspiciousFlags = @()
            $suspiciousFlags += $jvmArgs | Where-Object { $_ -like '*agent*' -or $_ -like '*javaagent*' }
            $suspiciousFlags += $jvmArgs | Where-Object { $_ -like '*instrument*' }
            $suspiciousFlags += $jvmArgs | Where-Object { $_ -like '*byteman*' }
            $suspiciousFlags += $jvmArgs | Where-Object { $_ -match '-Xbootclasspath/p:' }
            
            if ($suspiciousFlags.Count -gt 0) {
                Write-Host "  ⚠ SUSPICIOUS JVM FLAGS DETECTED:" -ForegroundColor Red
                foreach ($flag in $suspiciousFlags) {
                    Write-Host "    • $flag" -ForegroundColor Red
                }
                $verdictFlags.Add("Suspicious JVM flags detected: $($suspiciousFlags.Count)")
            }
            
            # Check for memory settings
            $memoryArgs = $jvmArgs | Where-Object { $_ -like '-Xmx*' -or $_ -like '-Xms*' -or $_ -like '-XX:Max*' -or $_ -like '-XX:Init*' }
            if ($memoryArgs.Count -gt 0) {
                Write-Host "  Memory Settings:" -ForegroundColor Cyan
                foreach ($memArg in $memoryArgs) {
                    Write-Host "    $memArg" -ForegroundColor White
                }
            }
            
            # Check for classpath manipulation
            $classpathArgs = $jvmArgs | Where-Object { $_ -like '-classpath*' -or $_ -like '-cp*' -or $_ -like '-Djava.class.path*' }
            if ($classpathArgs.Count -gt 0) {
                Write-Host "  Classpath Arguments:" -ForegroundColor Cyan
                foreach ($cpArg in $classpathArgs) {
                    Write-Host "    $cpArg" -ForegroundColor White
                }
            }
            
            # Check for debug/development flags
            $debugArgs = $jvmArgs | Where-Object { $_ -like '-agentlib:*jdwp*' -or $_ -like '-Xdebug*' -or $_ -like '-XX:+HeapDumpOnOutOfMemoryError*' }
            if ($debugArgs.Count -gt 0) {
                Write-Host "  Debug/Development Flags:" -ForegroundColor Yellow
                foreach ($debugArg in $debugArgs) {
                    Write-Host "    $debugArg" -ForegroundColor White
                }
            }
        }
        
        # Get JVM version information
        try {
            $jvmVersion = [System.Runtime.InteropServices.RuntimeInformation]::GetRuntimeInformation()
            if ($jvmVersion) {
                Write-Host "  JVM Version:" -ForegroundColor White
                Write-Host "    $($jvmVersion)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Could not determine JVM version" -ForegroundColor Yellow
        }
        
        # Check for loaded agents
        try {
            $loadedAgents = [System.Management.Management.ManagementObjectSearcher]::new()
            $loadedAgents.Query = "SELECT * FROM Win32_Process WHERE ProcessId=$processId"
            $loadedAgents.Get()
            
            if ($loadedAgents.Count -gt 0) {
                Write-Host "  Loaded Java Agents:" -ForegroundColor Yellow
                foreach ($agent in $loadedAgents) {
                    if ($agent.CommandLine -and $agent.CommandLine -like '*javaagent*') {
                        Write-Host "    $($agent.CommandLine)" -ForegroundColor White
                    }
                }
            }
        } catch {
            Write-Host "  Could not enumerate loaded agents" -ForegroundColor Yellow
        }
        
    }
} catch {
    Write-Host "  Error during JVM analysis: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Section 29 ---------------------------------------------
Write-Host "`nSECTION 29" -ForegroundColor Magenta
Write-Host "  This is a new section you requested" -ForegroundColor White
Write-Host "  Ready for your ideas and content" -ForegroundColor Green

# -- PARSE J FOR MODIFICATION -------------------------
Write-Host "`nJ MODIFICATION PARSER" -ForegroundColor Magenta
try {
    # Get all running Java processes
    $javaProcesses = Get-Process -Name java* -ErrorAction SilentlyContinue
    
    if ($javaProcesses.Count -eq 0) {
        Write-Host "  No Java processes found" -ForegroundColor Gray
    } else {
        Write-Host "  Found $($javaProcesses.Count) Java process(es):" -ForegroundColor White
        
        foreach ($proc in $javaProcesses) {
            Write-Host "  * $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Cyan
            
            # Check for J command line modifications
            try {
                $commandLine = (Get-WmiObject -Class Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                if ($commandLine) {
                    # Look for suspicious J flags
                    $suspiciousArgs = @()
                    
                    # Check for classpath injection
                    if ($commandLine -match '-classpath.*\.jar') {
                        $suspiciousArgs += "Classpath injection detected"
                    }
                    
                    # Check for agent injection
                    if ($commandLine -match '-javaagent') {
                        $suspiciousArgs += "Java agent injection detected"
                    }
                    
                    # Check for instrumentation
                    if ($commandLine -match '-javaagent.*instrument') {
                        $suspiciousArgs += "Java instrumentation detected"
                    }
                    
                    # Check for JAR modification
                    if ($commandLine -match '\.jar.*modify|\.jar.*replace|\.jar.*inject') {
                        $suspiciousArgs += "JAR modification detected"
                    }
                    
                    # Check for suspicious J options
                    $suspiciousJOptions = @('-Xbootclasspath/p:', '-Xshare:classes', '-XX:+UseContainerCgroup', '-XX:+UseContainerSupport')
                    foreach ($option in $suspiciousJOptions) {
                        if ($commandLine -match [regex]::Escape($option)) {
                            $suspiciousArgs += "Suspicious J option: $option"
                        }
                    }
                    
                    if ($suspiciousArgs.Count -gt 0) {
                        Write-Host "    ⚠ SUSPICIOUS J MODIFICATIONS:" -ForegroundColor Red
                        foreach ($arg in $suspiciousArgs) {
                            Write-Host "      • $arg" -ForegroundColor Red
                        }
                        $verdictFlags.Add("J modification detected in $($proc.ProcessName): $($suspiciousArgs.Count) issues")
                    } else {
                        Write-Host "    ✓ No suspicious J modifications detected" -ForegroundColor Green
                    }
                    
                    Write-Host "    Command Line: $commandLine" -ForegroundColor Gray
                }
            } catch {
                Write-Host "    Error analyzing command line: $($_.Exception.Message)" -ForegroundColor Red
            }
            
            # Check for loaded libraries
            try {
                $modules = $proc.Modules
                $suspiciousLibs = @()
                
                foreach ($module in $modules) {
                    $libName = $module.FileName.ToLower()
                    
                    # Check for suspicious library patterns
                    $suspiciousPatterns = @('*inject*', '*hook*', '*patch*', '*crack*', '*bypass*', '*cheat*')
                    foreach ($pattern in $suspiciousPatterns) {
                        if ($libName -like $pattern) {
                            $suspiciousLibs += $module.FileName
                        }
                    }
                    
                    # Check for unsigned libraries
                    try {
                        $signature = Get-AuthenticodeSignature -FilePath $module.FileName -ErrorAction SilentlyContinue
                        if (-not $signature -or $signature.Status -ne 'Valid') {
                            $suspiciousLibs += $module.FileName
                        }
                    } catch { }
                }
                
                if ($suspiciousLibs.Count -gt 0) {
                    Write-Host "    ⚠ SUSPICIOUS LIBRARIES:" -ForegroundColor Red
                    foreach ($lib in $suspiciousLibs) {
                        Write-Host "      • $lib" -ForegroundColor Red
                    }
                    $verdictFlags.Add("Suspicious libraries loaded in $($proc.ProcessName): $($suspiciousLibs.Count) libraries")
                } else {
                    Write-Host "    ✓ No suspicious libraries detected" -ForegroundColor Green
                }
                
                Write-Host "    Total modules: $($modules.Count)" -ForegroundColor Gray
            } catch {
                Write-Host "    Error analyzing modules: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "  Error during J modification analysis: $($_.Exception.Message)" -ForegroundColor Red
}

# -- DLLs injected into javaw.exe ------------------------------
Write-Host "`nJAVAW.EXE LOADED DLLs" -ForegroundColor Cyan
try {
    $mcProcDll = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $mcProcDll) { $mcProcDll = Get-Process java -ErrorAction SilentlyContinue }

    if (-not $mcProcDll) {
        Write-Host "  Minecraft is not running" -ForegroundColor Gray
    } else {
        # known-good DLL whitelist - system, JVM, and common legit libs
        $knownGoodPatterns = @(
            # Windows system paths
            '\\Windows\\System32\\',
            '\\Windows\\SysWOW64\\',
            '\\Windows\\Microsoft.NET\\',
            '\\Windows\\WinSxS\\',
            # JVM / Java runtime
            '\\jre\\', '\\jdk\\', '\\java\\', '\\openjdk\\', '\\zulu\\',
            '\\graalvm\\', '\\liberica\\', '\\corretto\\', '\\temurin\\',
            '\\adoptium\\', '\\semeru\\',
            # Minecraft launcher locations
            '\\Minecraft Launcher\\', '\\.minecraft\\', '\\minecraft\\',
            '\\MultiMC\\', '\\PrismLauncher\\', '\\ATLauncher\\',
            # Common legit injections
            'nvidia', 'nvd3d', 'nvcuda', 'nvoglv', 'ig4icd', 'igdumd',
            'amdvlk', 'atig6pxx', 'd3d', 'dxgi', 'opengl',
            'discord', 'steam', 'gameoverlayrenderer',
            'msvcp', 'msvcr', 'vcruntime', 'ucrtbase',
            'kernel32', 'ntdll', 'user32', 'gdi32', 'shell32',
            'advapi32', 'ole32', 'oleaut32', 'comctl32', 'comdlg32',
            'ws2_32', 'wininet', 'winhttp', 'crypt32', 'bcrypt',
            'sechost', 'rpcrt4', 'shlwapi', 'wldap32',
            'dwmapi', 'uxtheme', 'imm32', 'msctf', 'textinputframework',
            'coreclr', 'clr.dll', 'clrjit',
            'lwjgl', 'openal', 'jinput', 'jna-',
            'xaudio', 'audioses', 'mmdevapi'
        )

        $modules     = $mcProcDll.Modules | Sort-Object FileName
        $suspectDlls = [System.Collections.Generic.List[object]]::new()

        foreach ($mod in $modules) {
            $path  = $mod.FileName
            $lower = $path.ToLower()
            $isKnown = $false
            foreach ($pattern in $knownGoodPatterns) {
                if ($lower -contains $pattern.ToLower() -or $lower -like "*$($pattern.ToLower())*") {
                    $isKnown = $true; break
                }
            }
            if (-not $isKnown) { $suspectDlls.Add($mod) }
        }

        Write-Host ("  Total DLLs loaded: {0}" -f $modules.Count) -ForegroundColor White
        Write-Host "  - Don't ban for this its just helpful cus sometimes its real but it can also false flag to manualy check it" -ForegroundColor Gray

        if ($suspectDlls.Count -eq 0) {
            Write-Host "  No unexpected DLLs found" -ForegroundColor Green
        } else {
            Write-Host ("  UNEXPECTED DLLs: {0}" -f $suspectDlls.Count) -ForegroundColor Red
            foreach ($dll in $suspectDlls) {
                Write-Host "    ! " -NoNewline -ForegroundColor Red
                Write-Host ("{0,-35}" -f $dll.ModuleName) -NoNewline -ForegroundColor Yellow
                Write-Host $dll.FileName -ForegroundColor Gray
            }
            $verdictFlags.Add("Unexpected DLLs loaded into javaw.exe ($($suspectDlls.Count) found)")
        }
    }
} catch {
    Write-Host "  Error reading DLL list: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Process Tree Analysis --------------------------------------
Write-Host "`nPROCESS TREE ANALYSIS" -ForegroundColor Cyan
try {
    $mcProc = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $mcProc) { $mcProc = Get-Process java -ErrorAction SilentlyContinue }

    if (-not $mcProc) {
        Write-Host "  Minecraft is not running - cannot analyze process tree" -ForegroundColor Gray
    } else {
        Write-Host ("  Minecraft PID: {0}" -f $mcProc.Id) -ForegroundColor White
        Write-Host ("  Process Name: {0}" -f $mcProc.ProcessName) -ForegroundColor White
        Write-Host ("  Started: {0}" -f $mcProc.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White

        # Get parent process
        $parentProc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($mcProc.Id)" | ForEach-Object { 
            if ($_.ParentProcessId) { Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue }
        }

        if ($parentProc) {
            Write-Host ("  Parent Process: {0} (PID: {1})" -f $parentProc.ProcessName, $parentProc.Id) -ForegroundColor Yellow
            Write-Host ("  Parent Started: {0}" -f $parentProc.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
            
            # Check if parent is suspicious
            $suspiciousParents = @("cmd", "powershell", "wscript", "cscript", "rundll32", "mshta")
            if ($suspiciousParents -contains $parentProc.ProcessName.ToLower()) {
                Write-Host "  ! WARNING: Minecraft launched from suspicious parent process!" -ForegroundColor Red
                $verdictFlags.Add("Minecraft launched from suspicious parent process ($($parentProc.ProcessName))")
            }
        } else {
            Write-Host "  Parent Process: Unknown" -ForegroundColor Gray
        }

        # Get child processes
        $childProcs = Get-CimInstance -ClassName Win32_Process | Where-Object { $_.ParentProcessId -eq $mcProc.Id }
        if ($childProcs) {
            Write-Host ("  Child Processes: {0} found" -f $childProcs.Count) -ForegroundColor Yellow
            foreach ($child in $childProcs) {
                try {
                    $childProc = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
                    if ($childProc) {
                        Write-Host ("    * {0} (PID: {1}) - Started: {2}" -f $childProc.ProcessName, $childProc.Id, $childProc.StartTime.ToString("HH:mm:ss")) -ForegroundColor White
                        
                        # Check if child is suspicious
                        $suspiciousChildren = @("cmd", "powershell", "wscript", "cscript", "rundll32", "mshta", "regsvr32")
                        if ($suspiciousChildren -contains $childProc.ProcessName.ToLower()) {
                            Write-Host "      ! WARNING: Suspicious child process detected!" -ForegroundColor Red
                            $verdictFlags.Add("Suspicious child process spawned by Minecraft ($($childProc.ProcessName))")
                        }
                    }
                } catch { }
            }
        } else {
            Write-Host "  Child Processes: None" -ForegroundColor Green
        }

        # Analyze process tree depth and injection chains
        $processChain = @()
        $currentProc = $mcProc
        
        # Build process chain backwards
        for ($i = 0; $i -lt 5; $i++) {  # Limit depth to prevent infinite loops
            $parent = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($currentProc.Id)" | ForEach-Object { 
                if ($_.ParentProcessId) { Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue }
            }
            if ($parent) {
                $processChain = @($parent) + $processChain
                $currentProc = $parent
            } else {
                break
            }
        }

        if ($processChain.Count -gt 0) {
            Write-Host "  Process Chain Depth: {0}" -ForegroundColor Yellow
            foreach ($proc in $processChain) {
                Write-Host ("    -> {0} (PID: {1})" -f $proc.ProcessName, $proc.Id) -ForegroundColor Gray
            }
        }
    }
} catch {
    Write-Host "  Error during process tree analysis: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Hidden Files Detection in Mods Folder --------------------
Write-Host "`nHIDDEN FILES IN MODS FOLDER" -ForegroundColor Cyan
try {
    $modsRoot = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
    if (Test-Path $modsRoot) {
        $allFiles = Get-ChildItem -Path $modsRoot -Recurse -Force -ErrorAction SilentlyContinue
        $hiddenFiles = $allFiles | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::Hidden }
        $systemFiles = $allFiles | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::System }
        
        Write-Host ("  Total files in mods folder: {0}" -f $allFiles.Count) -ForegroundColor White
        
        if ($hiddenFiles.Count -gt 0) {
            Write-Host ("  Hidden files found: {0}" -f $hiddenFiles.Count) -ForegroundColor Red
            foreach ($file in $hiddenFiles) {
                Write-Host ("    ! {0}" -f $file.Name) -ForegroundColor Yellow
                $verdictFlags.Add("Hidden file found in mods folder: $($file.Name)")
            }
        } else {
            Write-Host "  No hidden files found" -ForegroundColor Green
        }
        
        if ($systemFiles.Count -gt 0) {
            Write-Host ("  System files found: {0}" -f $systemFiles.Count) -ForegroundColor Yellow
            foreach ($file in $systemFiles) {
                Write-Host ("    ? {0}" -f $file.Name) -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No system files found" -ForegroundColor Green
        }
    } else {
        Write-Host "  Mods folder not found at: $modsRoot" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Error checking for hidden files: $($_.Exception.Message)" -ForegroundColor Red
}

# Collect verdict signals from Part 1
# Defender off
$defenderKey  = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
$defenderPol  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
$rtpValue     = (Get-ItemProperty -Path $defenderKey  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
$polValue     = (Get-ItemProperty -Path $defenderPol  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
$rtpDisabled  = ($rtpValue -eq 1) -or ($polValue -eq 1)
if ($rtpDisabled) { $verdictWarnings.Add("Windows Defender real-time protection disabled") }

# Prefetch suspicious files
if ($suspiciousFiles.Count -gt 0) { $verdictWarnings.Add("Suspicious prefetch files found ($($suspiciousFiles.Count))") }

# Late JAR injection (reuse $suspiciousJars if in scope)
if ($suspiciousJars -and $suspiciousJars.Count -gt 0) { $verdictFlags.Add("Late-loaded JARs detected ($($suspiciousJars.Count))") }

# Event log cleared
$logCleared = Get-WinEvent -FilterHashtable @{LogName="System"; Id=@(104,1102)} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($logCleared) { $verdictWarnings.Add("Event log was cleared recently") }

Write-Host "`ndone." -ForegroundColor Cyan
try {
    $recycleBinPath = "$env:SystemDrive" + '\$Recycle.Bin'
    Write-Host "`nRECYCLE BIN" -ForegroundColor Magenta

    if (Test-Path $recycleBinPath) {
        $recycleBinFolder = Get-Item -LiteralPath $recycleBinPath -Force
        $userFolders      = Get-ChildItem -LiteralPath $recycleBinPath -Directory -Force -ErrorAction SilentlyContinue

        if ($userFolders) {
            $allDeletedItems = @()
            $latestModTime   = $recycleBinFolder.LastWriteTime

            foreach ($userFolder in $userFolders) {
                if ($userFolder.LastWriteTime -gt $latestModTime) { $latestModTime = $userFolder.LastWriteTime }
                $userItems = Get-ChildItem -LiteralPath $userFolder.FullName -File -Force -ErrorAction SilentlyContinue
                if ($userItems) {
                    $allDeletedItems += $userItems
                    $latestFile = $userItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latestFile -and $latestFile.LastWriteTime -gt $latestModTime) { $latestModTime = $latestFile.LastWriteTime }
                }
            }

            Write-Host "  Last Modified: " -NoNewline -ForegroundColor White
            Write-Host $latestModTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow

            if ($allDeletedItems.Count -gt 0) {
                Write-Host "  Total Items: "  -NoNewline -ForegroundColor White; Write-Host $allDeletedItems.Count -ForegroundColor Yellow
                $latestItem = $allDeletedItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                Write-Host "  Latest Item: "  -NoNewline -ForegroundColor White; Write-Host $latestItem.Name -ForegroundColor Gray
            } else {
                Write-Host "  Status: " -NoNewline -ForegroundColor White; Write-Host "Folders present but empty" -ForegroundColor Magenta
            }
        } else {
            Write-Host "  Status: "       -NoNewline -ForegroundColor White; Write-Host "Empty" -ForegroundColor Magenta
            Write-Host "  Last Modified: " -NoNewline -ForegroundColor White; Write-Host $recycleBinFolder.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Magenta
        }

        $clearEvent = Get-WinEvent -FilterHashtable @{LogName="System"; Id=10006} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($clearEvent) {
            Write-Host "  Last Cleared (Event): " -NoNewline -ForegroundColor White
            Write-Host $clearEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Red
        }
    } else {
        Write-Host "  Recycle Bin not found at: $recycleBinPath" -ForegroundColor Yellow
        Write-Host "  Note: Recycle Bin may be empty or on different drive" -ForegroundColor Gray
    }

    $consoleHistoryPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
    Write-Host "`n  CONSOLE HOST HISTORY" -ForegroundColor Magenta

    if (Test-Path $consoleHistoryPath) {
        $historyFile = Get-Item -Path $consoleHistoryPath -Force
        Write-Host "    Last Modified: " -NoNewline -ForegroundColor White
        Write-Host $historyFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Yellow
        $attributes = $historyFile.Attributes
        if ($attributes -ne "Archive") {
            Write-Host "    Attributes: " -NoNewline -ForegroundColor White; Write-Host $attributes -ForegroundColor Yellow
        } else {
            Write-Host "    Attributes: Normal" -ForegroundColor Magenta
        }
        $fileSize = $historyFile.Length
        Write-Host "    File Size: " -NoNewline -ForegroundColor White
        Write-Host "$([math]::Round($fileSize/1024, 2)) KB" -ForegroundColor Yellow
    } else {
        Write-Host "    File not found: $consoleHistoryPath" -ForegroundColor Yellow
        Write-Host "    Note: PowerShell history may be disabled or never used" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Error accessing system information: $($_.Exception.Message)" -ForegroundColor Red
}

# -- Logged-on users --------------------------------------------
Write-Host "`nLOGGED-ON USERS" -ForegroundColor Magenta
try {
    $sessions = Get-CimInstance -ClassName Win32_LogonSession -ErrorAction SilentlyContinue |
                Where-Object { $_.LogonType -in @(2, 10, 11) }  # Interactive, RemoteInteractive, CachedInteractive

    if ($sessions) {
        foreach ($session in $sessions) {
            $assoc = Get-CimAssociatedInstance -InputObject $session -ResultClassName Win32_UserAccount -ErrorAction SilentlyContinue
            if (-not $assoc) { $assoc = Get-CimAssociatedInstance -InputObject $session -ResultClassName Win32_UserAccount -ErrorAction SilentlyContinue }

            $username = if ($assoc) { "$($assoc.Domain)\$($assoc.Name)" } else {
                # fallback - grab from Win32_ComputerSystem
                (Get-CimInstance Win32_ComputerSystem).UserName
            }

            $logonTypeMap = @{ 2="Interactive"; 10="RemoteInteractive"; 11="CachedInteractive" }
            $logonType    = $logonTypeMap[[int]$session.LogonType]
            $startTime    = if ($session.StartTime) { $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }

            Write-Host "  * " -NoNewline -ForegroundColor Magenta
            Write-Host ("{0,-30}" -f $username) -NoNewline -ForegroundColor White
            Write-Host (" Type: {0,-22} Since: {1}" -f $logonType, $startTime) -ForegroundColor Yellow
        }
    } else {
        # simple fallback
        $currentUser = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($currentUser) {
            Write-Host "  * $currentUser" -ForegroundColor Magenta
        } else {
            Write-Host "  No active interactive sessions found" -ForegroundColor Magenta
        }
    }
} catch {
    Write-Host "  Error retrieving logged-on users: $($_.Exception.Message)" -ForegroundColor Red
}

# Collect verdict signals from Part 1
# Defender off
$defenderKey  = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
$defenderPol  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
$rtpValue     = (Get-ItemProperty -Path $defenderKey  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
$polValue     = (Get-ItemProperty -Path $defenderPol  -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
$rtpDisabled  = ($rtpValue -eq 1) -or ($polValue -eq 1)
if ($rtpDisabled) { $verdictWarnings.Add("Windows Defender real-time protection disabled") }

# Prefetch suspicious files
if ($suspiciousFiles.Count -gt 0) { $verdictWarnings.Add("Suspicious prefetch files found ($($suspiciousFiles.Count))") }

# Late JAR injection (reuse $suspiciousJars if in scope)
if ($suspiciousJars -and $suspiciousJars.Count -gt 0) { $verdictFlags.Add("Late-loaded JARs detected ($($suspiciousJars.Count))") }

# Event log cleared
$logCleared = Get-WinEvent -FilterHashtable @{LogName="System"; Id=@(104,1102)} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($logCleared) { $verdictWarnings.Add("Event log was cleared recently") }

Write-Host "`ndone." -ForegroundColor Cyan


# ============================================================
#  TRANSITION TO PART 2
# ============================================================
Write-Host ""
Write-Host ("=" * 76) -ForegroundColor Gray
Write-Host ""
Write-Host "  Press any key to continue to Mod Analyzer..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")


# ============================================================
#  PART 2 - VOID MOD ANALYZER
# ============================================================

$Banner = @"
I have aura
"@

Write-Host $Banner -ForegroundColor Magenta
Write-Host ""
Write-Host "                love yall " -ForegroundColor Gray -NoNewline
Write-Host "<3 "           -ForegroundColor Magenta -NoNewline
Write-Host "by "           -ForegroundColor Gray -NoNewline
Write-Host "AcousticVoid"  -ForegroundColor Magenta
Write-Host ""
Write-Host ("=" * 76) -ForegroundColor Gray
Write-Host

Write-Host "Enter path to the mods folder: " -NoNewline
Write-Host "(press Enter to use default)" -ForegroundColor Gray
$modsPath = Read-Host "PATH"
Write-Host

if ([string]::IsNullOrWhiteSpace($modsPath)) {
    $modsPath = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
    Write-Host "Continuing with " -NoNewline
    Write-Host $modsPath -ForegroundColor White
    Write-Host
}

if (-not (Test-Path $modsPath -PathType Container)) {
    Write-Host "Invalid Path!" -ForegroundColor Red
    Write-Host "The directory does not exist or is not accessible." -ForegroundColor Yellow
    Write-Host
    Write-Host "Tried to access: $modsPath" -ForegroundColor Gray
    Write-Host
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "Scanning directory: $modsPath" -ForegroundColor Magenta
Write-Host

$mcProcess = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $mcProcess) { $mcProcess = Get-Process java -ErrorAction SilentlyContinue }
if ($mcProcess) {
    try {
        $startTime = $mcProcess.StartTime
        $uptime    = (Get-Date) - $startTime
        Write-Host "{ Minecraft Uptime }" -ForegroundColor Gray
        Write-Host "   $($mcProcess.Name) PID $($mcProcess.Id) started at $startTime" -ForegroundColor Gray
        Write-Host "   Running for: $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s" -ForegroundColor Gray
        Write-Host ""
    } catch { }
}

# -- Helper functions -----------------------------------------
# Obfuscated function names
function AV-Show-Progress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity,
        [string]$Status = "Processing"
    )
    
    $percentComplete = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $progressBar = "[$percentComplete%] "
    $barLength = 30
    $filledLength = [math]::Round(($percentComplete / 100) * $barLength)
    $emptyLength = $barLength - $filledLength
    
    $progressBar += "[" + ("#" * $filledLength) + (" " * $emptyLength) + "]"
    
    Write-Host "`r$progressBar $Activity - $Status ($Current/$Total)" -NoNewline -ForegroundColor Cyan
    if ($Current -eq $Total) { Write-Host "" }
}

function Get-FileSHA1 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA1).Hash
}

function Get-DownloadSource {
    param([string]$Path)
    $zoneData = Get-Content -Raw -Stream Zone.Identifier $Path -ErrorAction SilentlyContinue
    if ($zoneData -match "HostUrl=(.+)") {
        $url = $matches[1].Trim()
        if ($url -match "mediafire\.com")                                        { return "MediaFire" }
        elseif ($url -match "discord\.com|discordapp\.com|cdn\.discordapp\.com") { return "Discord" }
        elseif ($url -match "dropbox\.com")                                      { return "Dropbox" }
        elseif ($url -match "drive\.google\.com")                                { return "Google Drive" }
        elseif ($url -match "mega\.nz|mega\.co\.nz")                             { return "MEGA" }
        elseif ($url -match "github\.com")                                       { return "GitHub" }
        elseif ($url -match "modrinth\.com")                                     { return "Modrinth" }
        elseif ($url -match "curseforge\.com")                                   { return "CurseForge" }
        elseif ($url -match "anydesk\.com")                                      { return "AnyDesk" }
        elseif ($url -match "doomsdayclient\.com")                               { return "DoomsdayClient" }
        elseif ($url -match "prestigeclient\.vip")                               { return "PrestigeClient" }
        elseif ($url -match "198macros\.com")                                    { return "198Macros" }
        else {
            if ($url -match "https?://(?:www\.)?([^/]+)") { return $matches[1] }
            return $url
        }
    }
    return $null
}

function Query-Modrinth {
    param([string]$Hash)
    try {
        $versionInfo = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_file/$Hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if ($versionInfo.project_id) {
            $projectInfo = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/$($versionInfo.project_id)" -Method Get -UseBasicParsing -ErrorAction Stop
            return @{ Name = $projectInfo.title; Slug = $projectInfo.slug }
        }
    } catch { }
    return @{ Name = ""; Slug = "" }
}

function Query-Megabase {
    param([string]$Hash)
    try {
        $result = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$Hash" -Method Get -UseBasicParsing -ErrorAction Stop
        if (-not $result.error) { return $result.data }
    } catch { }
    return $null
}

# -- Detection lists -------------------------------------------
$suspiciousPatterns = @(
    "AimAssist", "AnchorTweaks", "AutoAnchor", "AutoCrystal", "AutoDoubleHand",
    "AutoHitCrystal", "AutoPot", "AutoTotem", "AutoArmor", "InventoryTotem",
    "Hitboxes", "JumpReset", "LegitTotem", "PingSpoof", "SelfDestruct",
    "ShieldBreaker", "TriggerBot", "Velocity", "AxeSpam", "WebMacro",
    "FastPlace", "WalskyOptimizer", "WalksyOptimizer", "walsky.optimizer",
    "WalksyCrystalOptimizerMod", "Donut", "Replace Mod", "Reach",
    "ShieldDisabler", "SilentAim", "Totem Hit", "Wtap", "FakeLag",
    "BlockESP", "dev.krypton", "Virgin", "AntiMissClick",
    "LagReach", "PopSwitch", "SprintReset", "ChestSteal", "AntiBot",
    "ElytraSwap", "FastXP", "FastExp", "Refill", "NoJumpDelay", "AirAnchor",
    "jnativehook", "FakeInv", "HoverTotem", "AutoClicker", "AutoFirework",
    "PackSpoof", "Antiknockback", "scrim", "catlean", "Argon",
    "AuthBypass", "Asteria", "Prestige", "AutoEat", "AutoMine",
    "MaceSwap", "DoubleAnchor", "AutoTPA", "BaseFinder", "Xenon", "gypsy",
    "Grim", "grim",
    "org.chainlibs.module.impl.modules.Crystal.Y",
    "org.chainlibs.module.impl.modules.Crystal.bF",
    "org.chainlibs.module.impl.modules.Crystal.bM",
    "org.chainlibs.module.impl.modules.Crystal.bY",
    "org.chainlibs.module.impl.modules.Crystal.bq",
    "org.chainlibs.module.impl.modules.Crystal.cv",
    "org.chainlibs.module.impl.modules.Crystal.o",
    "org.chainlibs.module.impl.modules.Blatant.I",
    "org.chainlibs.module.impl.modules.Blatant.bR",
    "org.chainlibs.module.impl.modules.Blatant.bx",
    "org.chainlibs.module.impl.modules.Blatant.cj",
    "org.chainlibs.module.impl.modules.Blatant.dk",
    "imgui", "imgui.gl3", "imgui.glfw",
    "BowAim", "Criticals", "Flight", "Fakenick", "FakeItem",
    "invsee", "ItemExploit", "Hellion", "hellion",
    "LicenseCheckMixin", "ClientPlayerInteractionManagerAccessor",
    "ClientPlayerEntityMixim", "dev.gambleclient", "obfuscatedAuth",
    "phantom-refmap.json", "xyz.greaj",
    "ji.class", "hu.class", "bu.class", "pu.class", "ta.class",
    "ne.class", "so.class", "na.class", "do.class", "gu.class",
    "zu.class", "de.class", "tsu.class", "be.class", "se.class",
    "to.class", "mi.class", "bi.class", "su.class", "no.class"
)

$cheatStrings = @(
    "AutoCrystal", "autocrystal", "auto crystal", "cw crystal",
    "dontPlaceCrystal", "dontBreakCrystal",
    "AutoHitCrystal", "autohitcrystal", "canPlaceCrystalServer", "healPotSlot",
    "AutoAnchor", "autoanchor", "auto anchor", "DoubleAnchor",
    "hasGlowstone", "HasAnchor", "anchortweaks", "anchor macro", "safe anchor", "safeanchor",
    "AutoTotem", "autototem", "auto totem", "InventoryTotem",
    "inventorytotem", "HoverTotem", "hover totem", "legittotem",
    "AutoPot", "autopot", "auto pot", "speedPotSlot", "strengthPotSlot",
    "AutoArmor", "autoarmor", "auto armor",
    "preventSwordBlockBreaking", "preventSwordBlockAttack",
    "AutoDoubleHand", "autodoublehand", "auto double hand",
    "AutoClicker",
    "Failed to switch to mace after axe!",
    "Breaking shield with axe...",
    "Donut", "JumpReset", "axespam", "axe spam",
    "shieldbreaker", "shield breaker", "EndCrystalItemMixin",
    "findKnockbackSword", "attackRegisteredThisClick",
    "AimAssist", "aimassist", "aim assist",
    "triggerbot", "trigger bot",
    "FakeInv", "Friends", "swapBackToOriginalSlot",
    "FakeLag", "pingspoof", "ping spoof", "velocity",
    "webmacro", "web macro",
    "lvstrng", "dqrkis", "selfdestruct", "self destruct",
    "AutoMace", "AutoFirework", "MaceSwap", "AirAnchor",
    "ElytraSwap", "FastXP", "FastExp", "NoJumpDelay",
    "PackSpoof", "Antiknockback", "scrim", "catlean",
    "AuthBypass", "obfuscatedAuth", "LicenseCheckMixin",
    "BaseFinder", "invsee", "ItemExploit",
    "NoFall", "nofall",
    "WalksyCrystalOptimizerMod", "WalksyOptimizer", "WalskyOptimizer",
    "autoCrystalPlaceClock",
    "setBlockBreakingCooldown", "getBlockBreakingCooldown", "blockBreakingCooldown",
    "onBlockBreaking", "setItemUseCooldown",
    "setSelectedSlot", "invokeDoAttack", "invokeDoItemUse", "invokeOnMouseButton",
    "onTickMovement", "onIsGlowing", "onPushOutOfBlocks",
    "Automatically switches to sword when hitting with totem",
    "arrayOfString", "POT_CHEATS",
    "Dqrkis Client", "Entity.isGlowing"
)

# -- Bypass / injection scan -----------------------------------
function Invoke-BypassScan {
    param([string]$FilePath)

    $flags = [System.Collections.Generic.List[string]]::new()
    $jarName = [System.IO.Path]::GetFileName($FilePath)

    # Basic file checks
    if (-not (Test-Path $FilePath)) {
        $flags.Add("File not accessible: $FilePath")
        return $flags
    }

    # Check for suspicious JAR name patterns
    if (-not (Test-SuspiciousJarName -JarName $jarName)) {
        $flags.Add("Suspicious JAR name: $jarName")
    }

    # Check file size (suspicious if > 50MB)
    $fileSize = (Get-Item $FilePath).Length / 1MB
    if ($fileSize -gt 50) {
        $flags.Add("Large file size: $([math]::Round($fileSize, 2)) MB")
    }

    # Check for nested JARs
    $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
    $nestedJars = $zip.Entries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" }
    if ($nestedJars.Count -gt 0) {
        $flags.Add("Contains nested JARs ($($nestedJars.Count) found)")
    }
    $zip.Dispose()

    # Check for unsigned JARs (no signature)
    $signature = Get-AuthenticodeSignature $FilePath -ErrorAction SilentlyContinue
    if (-not $signature) {
        $flags.Add("Unsigned JAR file")
    }

    # Hash lookup against known cheat databases
    $sha1Hash = Get-FileSHA1 -Path $FilePath
    $modrinthInfo = Query-Modrinth -Hash $sha1Hash
    $megabaseInfo = Query-Megabase -Hash $sha1Hash

    if ($modrinthInfo.Name) {
        $flags.Add("Modrinth match: $($modrinthInfo.Name) (slug: $($modrinthInfo.Slug))")
    }

    if ($megabaseInfo) {
        $flags.Add("Megabase match: $($megabaseInfo.name)")
    }

    return $flags
}

# -- Pattern + string scan -------------------------------------
function Invoke-ModScan {
    param([string]$FilePath)

    $jarName = [System.IO.Path]::GetFileName($FilePath)
    $scanResults = [System.Collections.Generic.List[object]]::new()

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)

    # Scan for suspicious patterns in file names and paths
    foreach ($pattern in $suspiciousPatterns) {
        if ($jarName -like "*$pattern*" -or $FilePath -like "*$pattern*") {
            $scanResults.Add([PSCustomObject]@{
                Type = "Pattern Match"
                Pattern = $pattern
                Location = "Filename/Path"
                Details = "Found in name or path"
            })
        }
    }

    # Scan all entries for suspicious strings
    $allEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $zip.Entries) { $allEntries.Add($entry) }

    $totalEntries = $allEntries.Count
    $processedEntries = 0

    foreach ($entry in $allEntries) {
        $processedEntries++
        AV-Show-Progress -Current $processedEntries -Total $totalEntries -Activity "Scanning $jarName" -Status "Analyzing entries"

        try {
            $s = $entry.Open()
            $reader = [System.IO.StreamReader]::new($s)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $s.Close()

            $foundPatterns = [System.Collections.Generic.HashSet[string]]::new()

            foreach ($cheat in $cheatStrings) {
                if ($content -like "*$cheat*" -or $content -cmatch $cheat) {
                    $foundPatterns.Add($cheat)
                }
            }

            if ($foundPatterns.Count -gt 0) {
                $scanResults.Add([PSCustomObject]@{
                    Type = "String Match"
                    Pattern = ($foundPatterns -join ", ")
                    Location = $entry.FullName
                    Details = "Found in class content"
                })
            }
        } catch {
            $scanResults.Add([PSCustomObject]@{
                Type = "Scan Error"
                Pattern = "N/A"
                Location = $entry.FullName
                Details = "Error reading entry: $($_.Exception.Message)"
            })
        }
    }

    $zip.Dispose()
    Write-Host "" -NoNewline
    return $scanResults
}

# -- Scan passes -----------------------------------------------
# Pass 1 - hash lookup
Write-Host "`n[HASH LOOKUP]" -ForegroundColor Cyan
$hashLookupResults = [System.Collections.Generic.List[object]]::new()

# Pass 2 - deep scan
Write-Host "`n[DEEP SCAN]" -ForegroundColor Cyan
$deepScanResults = [System.Collections.Generic.List[object]]::new()

# Pass 3 - bypass scan
Write-Host "`n[BYPASS SCAN]" -ForegroundColor Cyan
$bypassScanResults = [System.Collections.Generic.List[object]]::new()

# -- Results --------------------------------------------------
Write-Host "`n[SCAN RESULTS]" -ForegroundColor Cyan
Write-Host "=" * 76 -ForegroundColor Gray

$allMods = Get-ChildItem -Path $modsPath -Filter *.jar -File -Force -ErrorAction SilentlyContinue
$totalMods = $allMods.Count
$processedMods = 0

if ($totalMods -eq 0) {
    Write-Host "No JAR files found in $modsPath" -ForegroundColor Yellow
} else {
    foreach ($mod in $allMods) {
        $processedMods++
        AV-Show-Progress -Current $processedMods -Total $totalMods -Activity "Scanning mods" -Status "Processing $($mod.Name)"

        $modResults = [System.Collections.Generic.List[object]]::new()

        # Hash lookup
        $hashFlags = Invoke-BypassScan -FilePath $mod.FullName
        $modResults.AddRange($hashFlags)

        # Deep scan
        $deepFlags = Invoke-ModScan -FilePath $mod.FullName
        $modResults.AddRange($deepFlags)

        # Bypass scan
        $bypassFlags = Invoke-BypassScan -FilePath $mod.FullName
        $modResults.AddRange($bypassFlags)

        if ($modResults.Count -gt 0) {
            $hashLookupResults.AddRange([PSCustomObject]@{
                ModName = $mod.Name
                Size = [math]::Round(($mod.Length / 1MB), 2)
                Flags = $modResults
                Risk = "High"
            })
            $deepScanResults.AddRange([PSCustomObject]@{
                ModName = $mod.Name
                Size = [math]::Round(($mod.Length / 1MB), 2)
                Flags = $modResults
                Risk = "Critical"
            })
            $bypassScanResults.AddRange([PSCustomObject]@{
                ModName = $mod.Name
                Size = [math]::Round(($mod.Length / 1MB), 2)
                Flags = $modResults
                Risk = "Critical"
            })
        }
    }

    Write-Host "" -NoNewline

    # Display results
    Write-Host "HASH LOOKUP RESULTS:" -ForegroundColor Yellow
    if ($hashLookupResults.Count -gt 0) {
        foreach ($result in $hashLookupResults) {
            Write-Host "  +--- " -ForegroundColor Red -NoNewline
            Write-Host " | MOD: $($result.ModName) ($([math]::Round($result.Size, 2)) MB)" -ForegroundColor Red
            foreach ($flag in $result.Flags) {
                Write-Host " | FLAG: $flag" -ForegroundColor Red
            }
            Write-Host " | RISK: $($result.Risk)" -ForegroundColor Red
            Write-Host " +--- " -ForegroundColor Red
        }
    } else {
        Write-Host "  No suspicious hashes found" -ForegroundColor Green
    }

    Write-Host "`nDEEP SCAN RESULTS:" -ForegroundColor Yellow
    if ($deepScanResults.Count -gt 0) {
        foreach ($result in $deepScanResults) {
            Write-Host "  +--- " -ForegroundColor Red -NoNewline
            Write-Host " | MOD: $($result.ModName) ($([math]::Round($result.Size, 2)) MB)" -ForegroundColor Red
            foreach ($flag in $result.Flags) {
                Write-Host " | FLAG: $flag" -ForegroundColor Red
            }
            Write-Host " | RISK: $($result.Risk)" -ForegroundColor Red
            Write-Host " +--- " -ForegroundColor Red
        }
    } else {
        Write-Host "  No suspicious patterns found" -ForegroundColor Green
    }

    Write-Host "`nBYPASS SCAN RESULTS:" -ForegroundColor Yellow
    if ($bypassScanResults.Count -gt 0) {
        foreach ($result in $bypassScanResults) {
            Write-Host "  +--- " -ForegroundColor Red -NoNewline
            Write-Host " | MOD: $($result.ModName) ($([math]::Round($result.Size, 2)) MB)" -ForegroundColor Red
            foreach ($flag in $result.Flags) {
                Write-Host " | FLAG: $flag" -ForegroundColor Red
            }
            Write-Host " | RISK: $($result.Risk)" -ForegroundColor Red
            Write-Host " +--- " -ForegroundColor Red
        }
    } else {
        Write-Host "  No bypass techniques found" -ForegroundColor Green
    }

    Write-Host "=" * 76 -ForegroundColor Gray
}

# -- Collect Part 2 verdict signals ----------------------------
$totalSuspicious = ($hashLookupResults + $deepScanResults + $bypassScanResults).Count
if ($totalSuspicious -gt 0) {
    $verdictFlags.Add("Suspicious mods detected: $totalSuspicious")
}

# -- FINAL VERDICT ---------------------------------------------
Write-Host "`n" -ForegroundColor Cyan
Write-Host "=" * 76 -ForegroundColor Gray
Write-Host "" -ForegroundColor Cyan
Write-Host "FINAL VERDICT" -ForegroundColor Red -NoNewline
Write-Host "=" * 76 -ForegroundColor Gray

$allIssues = $verdictFlags + $verdictWarnings
if ($allIssues.Count -eq 0) {
    Write-Host "✓ SYSTEM APPEARS CLEAN" -ForegroundColor Green
} else {
    Write-Host "⚠ ISSUES DETECTED:" -ForegroundColor Yellow

    if ($verdictFlags.Count -gt 0) {
        Write-Host "  CRITICAL FLAGS:" -ForegroundColor Red
        foreach ($flag in $verdictFlags) { Write-Host "    • $flag" -ForegroundColor Red }
    }

    if ($verdictWarnings.Count -gt 0) {
        Write-Host "  WARNINGS:" -ForegroundColor Yellow
        foreach ($warning in $verdictWarnings) { Write-Host "    • $warning" -ForegroundColor Yellow }
    }
}

Write-Host "" -ForegroundColor Cyan
Write-Host "Scan completed. Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
