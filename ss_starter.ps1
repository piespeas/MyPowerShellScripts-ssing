$isAdmin = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║           ADMINISTRATOR PRIVILEGES REQUIRED       ║" -ForegroundColor Red
    Write-Host "║     Please run this script as Administrator!      ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Red
    exit
}

Write-Host "by AcousticVoid" -ForegroundColor DarkMagenta
Write-Host ""

try {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Write-Host "SYSTEM BOOT TIME" -ForegroundColor DarkMagenta
    Write-Host ("  Last Boot: {0}" -f $bootTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("  Uptime: {0} days, {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor White
} catch {
    Write-Host "Unable to retrieve boot time information" -ForegroundColor Red
}

$drives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    Write-Host "`nCONNECTED DRIVES" -ForegroundColor DarkMagenta
    foreach ($drive in $drives) {
        Write-Host ("  {0}: {1}" -f $drive.DeviceID, $drive.FileSystem) -ForegroundColor Magenta
    }
}

Write-Host "`nSERVICE STATUS" -ForegroundColor DarkMagenta

$services = @(
    @{Name = "SysMain"; DisplayName = "SysMain"},
    @{Name = "PcaSvc"; DisplayName = "Program Compatibility Assistant Service"},
    @{Name = "DPS"; DisplayName = "Diagnostic Policy Service"},
    @{Name = "EventLog"; DisplayName = "Windows Event Log"},
    @{Name = "Schedule"; DisplayName = "Task Scheduler"},
    @{Name = "Bam"; DisplayName = "Background Activity Moderator"},
    @{Name = "Dusmsvc"; DisplayName = "Data Usage"},
    @{Name = "Appinfo"; DisplayName = "Application Information"},
    @{Name = "CDPSvc"; DisplayName = "Connected Devices Platform Service"},
    @{Name = "DcomLaunch"; DisplayName = "DCOM Server Process Launcher"},
    @{Name = "PlugPlay"; DisplayName = "Plug and Play"},
    @{Name = "wsearch"; DisplayName = "Windows Search"}
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) {
                $displayName = $displayName.Substring(0, 37) + "..."
            }
            Write-Host ("  {0,-12} {1,-40}" -f $svc.Name, $displayName) -ForegroundColor Magenta -NoNewline

            if ($svc.Name -eq "Bam") {
                Write-Host " | Enabled" -ForegroundColor DarkYellow
            } else {
                try {
                    $process = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object ProcessId
                    if ($process.ProcessId -gt 0) {
                        $proc = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
                        if ($proc) {
                            Write-Host (" | {0}" -f $proc.StartTime.ToString("HH:mm:ss")) -ForegroundColor DarkYellow
                        } else {
                            Write-Host " | N/A" -ForegroundColor DarkYellow
                        }
                    } else {
                        Write-Host " | N/A" -ForegroundColor DarkYellow
                    }
                } catch {
                    Write-Host " | N/A" -ForegroundColor DarkYellow
                }
            }
        } else {
            $displayName = $service.DisplayName
            if ($displayName.Length -gt 40) {
                $displayName = $displayName.Substring(0, 37) + "..."
            }
            Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, $displayName, $service.Status) -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} {1,-40} {2}" -f $svc.Name, "Not Found", "Stopped") -ForegroundColor DarkGray
    }
}

Write-Host "`nREGISTRY" -ForegroundColor DarkMagenta

$settings = @(
    @{ Name = "CMD"; Path = "HKCU:\Software\Policies\Microsoft\Windows\System"; Key = "DisableCMD"; Warning = "Disabled"; Safe = "Available" },
    @{ Name = "PowerShell Logging"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"; Key = "EnableScriptBlockLogging"; Warning = "Disabled"; Safe = "Enabled" },
    @{ Name = "Activities Cache"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Key = "EnableActivityFeed"; Warning = "Disabled"; Safe = "Enabled" },
    @{ Name = "Prefetch Enabled"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key = "EnablePrefetcher"; Warning = "Disabled"; Safe = "Enabled" }
)

foreach ($s in $settings) {
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

function Check-EventLog {
    param ($logName, $eventID, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$eventID]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor DarkYellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Magenta
    }
}

function Check-RecentEventLog {
    param ($logName, $eventIDs, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$($eventIDs -join ' or EventID=')]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message (ID: $($event.Id)) at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor DarkYellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Magenta
    }
}

function Check-DeviceDeleted {
    try {
        $event = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) {
            Write-Host "  Device configuration changed at: " -NoNewline -ForegroundColor White
            Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor DarkYellow
            return
        }
    } catch {}

    try {
        $event = Get-WinEvent -FilterHashtable @{LogName="System"; ID=225} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($event) {
            Write-Host "  Device removed at: " -NoNewline -ForegroundColor White
            Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor DarkYellow
            return
        }
    } catch {}

    try {
        $events = Get-WinEvent -LogName "System" | Where-Object {$_.Id -eq 225 -or $_.Id -eq 400} | Sort-Object TimeCreated -Descending | Select-Object -First 1
        if ($events) {
            Write-Host "  Last device change at: " -NoNewline -ForegroundColor White
            Write-Host $events.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor DarkYellow
            return
        }
    } catch {}

    Write-Host "  Device changes - No records found" -ForegroundColor Magenta
}

Write-Host "`nEVENT LOGS" -ForegroundColor DarkMagenta

Check-EventLog "Application" 3079 "USN Journal cleared"
Check-RecentEventLog "System" @(104, 1102) "Event Logs cleared"
Check-EventLog "System" 1074 "Last PC Shutdown"
Check-EventLog "Security" 4616 "System time changed"
Check-EventLog "System" 6005 "Event Log Service started"
Check-DeviceDeleted


$prefetchPath = "$env:SystemRoot\Prefetch"
if (Test-Path $prefetchPath) {
    Write-Host "`nPREFETCH INTEGRITY" -ForegroundColor DarkMagenta

    $files = Get-ChildItem -Path $prefetchPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  No prefetch found?? Check the folder please" -ForegroundColor DarkYellow
    } else {
        $hashTable = @{}
        $suspiciousFiles = @{}
        $totalFiles = $files.Count

        $hiddenFiles = @()
        $readOnlyFiles = @()
        $hiddenAndReadOnlyFiles = @()
        $errorFiles = @()

        foreach ($file in $files) {
            try {
                $isHidden = $file.Attributes -band [System.IO.FileAttributes]::Hidden
                $isReadOnly = $file.Attributes -band [System.IO.FileAttributes]::ReadOnly

                if ($isHidden -and $isReadOnly) {
                    $hiddenAndReadOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "Hidden and Read-only"
                    }
                } elseif ($isHidden) {
                    $hiddenFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "Hidden file"
                    }
                } elseif ($isReadOnly) {
                    $readOnlyFiles += $file
                    if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                        $suspiciousFiles[$file.Name] = "Read-only file"
                    }
                }

                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($hash) {
                    if ($hashTable.ContainsKey($hash.Hash)) {
                        $hashTable[$hash.Hash].Add($file.Name)
                    } else {
                        $hashTable[$hash.Hash] = [System.Collections.Generic.List[string]]::new()
                        $hashTable[$hash.Hash].Add($file.Name)
                    }
                }
            } catch {
                $errorFiles += $file
                if (-not $suspiciousFiles.ContainsKey($file.Name)) {
                    $suspiciousFiles[$file.Name] = "Error analyzing file: $($_.Exception.Message)"
                }
            }
        }

        if ($hiddenAndReadOnlyFiles.Count -gt 0) {
            Write-Host "  Hidden & Read-only Files: $($hiddenAndReadOnlyFiles.Count) found" -ForegroundColor DarkYellow
            foreach ($file in $hiddenAndReadOnlyFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        }

        if ($hiddenFiles.Count -gt 0) {
            Write-Host "  Hidden Files: $($hiddenFiles.Count) found" -ForegroundColor DarkYellow
            foreach ($file in $hiddenFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        } else {
            Write-Host "  Hidden Files: None" -ForegroundColor Magenta
        }

        if ($readOnlyFiles.Count -gt 0) {
            Write-Host "  Read-Only Files: $($readOnlyFiles.Count)" -ForegroundColor DarkYellow
            foreach ($file in $readOnlyFiles) {
                Write-Host ("    {0}" -f $file.Name) -ForegroundColor White
            }
        } else {
            Write-Host "  Read-Only Files: None" -ForegroundColor Magenta
        }

        $repeatedHashes = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($repeatedHashes) {
            Write-Host "  Duplicate Files: $($repeatedHashes.Count) sets found" -ForegroundColor DarkYellow
            foreach ($entry in $repeatedHashes) {
                foreach ($file in $entry.Value) {
                    if (-not $suspiciousFiles.ContainsKey($file)) {
                        $suspiciousFiles[$file] = "Duplicate file"
                    }
                }
                Write-Host ("    Duplicate set: {0}" -f ($entry.Value -join ", ")) -ForegroundColor White
            }
        } else {
            Write-Host "  Duplicates: None" -ForegroundColor Magenta
        }

        if ($suspiciousFiles.Count -gt 0) {
            Write-Host "`n  SUSPICIOUS FILES FOUND: $($suspiciousFiles.Count)/$totalFiles" -ForegroundColor DarkYellow
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

try {
    $recycleBinPath = "$env:SystemDrive" + '\$Recycle.Bin'

    Write-Host "`nRECYCLE BIN" -ForegroundColor DarkMagenta

    if (Test-Path $recycleBinPath) {
        $recycleBinFolder = Get-Item -LiteralPath $recycleBinPath -Force
        $userFolders = Get-ChildItem -LiteralPath $recycleBinPath -Directory -Force -ErrorAction SilentlyContinue

        if ($userFolders) {
            $allDeletedItems = @()
            $latestModTime = $recycleBinFolder.LastWriteTime

            foreach ($userFolder in $userFolders) {
                if ($userFolder.LastWriteTime -gt $latestModTime) {
                    $latestModTime = $userFolder.LastWriteTime
                }

                $userItems = Get-ChildItem -LiteralPath $userFolder.FullName -File -Force -ErrorAction SilentlyContinue
                if ($userItems) {
                    $allDeletedItems += $userItems

                    $latestFile = $userItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latestFile -and $latestFile.LastWriteTime -gt $latestModTime) {
                        $latestModTime = $latestFile.LastWriteTime
                    }
                }
            }

            Write-Host "  Last Modified: " -NoNewline -ForegroundColor White
            Write-Host $latestModTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor DarkYellow

            if ($allDeletedItems.Count -gt 0) {
                Write-Host "  Total Items: " -NoNewline -ForegroundColor White
                Write-Host $allDeletedItems.Count -ForegroundColor DarkYellow

                $latestItem = $allDeletedItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                Write-Host "  Latest Item: " -NoNewline -ForegroundColor White
                Write-Host $latestItem.Name -ForegroundColor DarkGray
            } else {
                Write-Host "  Status: " -NoNewline -ForegroundColor White
                Write-Host "Folders present but empty" -ForegroundColor Magenta
            }
        } else {
            Write-Host "  Status: " -NoNewline -ForegroundColor White
            Write-Host "Emptyy" -ForegroundColor Magenta
            Write-Host "  Last Modified: " -NoNewline -ForegroundColor White
            Write-Host $recycleBinFolder.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Magenta
        }

        $clearEvent = Get-WinEvent -FilterHashtable @{LogName="System"; Id=10006} -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($clearEvent) {
            Write-Host "  Last Cleared (Event): " -NoNewline -ForegroundColor White
            Write-Host $clearEvent.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor Red
        }
    } else {
        Write-Host "  Recycle Bin not found at: $recycleBinPath" -ForegroundColor DarkYellow
        Write-Host "  Note: Recycle Bin may be empty or on different drive" -ForegroundColor DarkGray
    }


    $consoleHistoryPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
    Write-Host "`n  CONSOLE HOST HISTORY" -ForegroundColor DarkMagenta

    if (Test-Path $consoleHistoryPath) {
        $historyFile = Get-Item -Path $consoleHistoryPath -Force
        Write-Host "    Last Modified: " -NoNewline -ForegroundColor White
        Write-Host $historyFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor DarkYellow

        $attributes = $historyFile.Attributes
        if ($attributes -ne "Archive") {
            Write-Host "    Attributes: " -NoNewline -ForegroundColor White
            Write-Host $attributes -ForegroundColor DarkYellow
        } else {
            Write-Host "    Attributes: Normal" -ForegroundColor Magenta
        }

        $fileSize = $historyFile.Length
        Write-Host "    File Size: " -NoNewline -ForegroundColor White
        Write-Host "$([math]::Round($fileSize/1024, 2)) KB" -ForegroundColor DarkYellow

    } else {
        Write-Host "    File not found: $consoleHistoryPath" -ForegroundColor DarkYellow
        Write-Host "    Note: PowerShell history may be disabled or never used" -ForegroundColor DarkGray
    }

} catch {
    Write-Host "  Error accessing system information: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`ndone." -ForegroundColor DarkMagenta