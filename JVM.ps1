# Don't use JVM!!!

$Results = @()
$ClasspathResults = @()
$ScanTime = Get-Date

$Patterns = @{
    "Memory" = @(
        "-Xmx*",
        "-Xms*"
    )

    "Injected Mods" = @(
        "-javaagent*",
        "-Dfabric.addMods*",
        "-Dloader.addMods*"
    )

    "Tweakers" = @(
        "--tweakClass*"
    )

    "Mixin" = @(
        "-Dmixin*"
    )

    "Native Libraries" = @(
        "-Djava.library.path*"
    )

    "Fabric" = @(
        "-Dfabric.classPathGroups*",
        "-Dfabric.gameJarPath*",
        "-Dfabric.remapClasspathFile*"
    )

    "Launch Information" = @(
        "--launchTarget*",
        "--gameDir*",
        "--assetsDir*",
        "--version*"
    )
}

$Processes = Get-CimInstance Win32_Process -Filter "Name='javaw.exe'" |
             Sort-Object ProcessId


if (-not $Processes) {
    Write-Host "No javaw.exe processes found." -ForegroundColor Yellow
    return
}


foreach ($Process in $Processes) {

    $ProcessID = $Process.ProcessId
    $CommandLine = $Process.CommandLine
    $Started = $Process.CreationDate

    $Runtime = (Get-Date) - $Started
    $RuntimeText = "{0}h {1}m {2}s" -f `
        $Runtime.Hours,
        $Runtime.Minutes,
        $Runtime.Seconds


    if ([string]::IsNullOrWhiteSpace($CommandLine)) {

        $Results += [PSCustomObject]@{
            PID      = $ProcessID
            Started  = $Started
            Runtime  = $RuntimeText
            Detected = $ScanTime
            Category = "Error"
            Details  = "Command line unavailable"
        }

        continue
    }


    $Arguments = $CommandLine -split ' (?=-)'


    #
    # JVM Arguments
    #

    foreach ($Category in $Patterns.Keys) {

        $Matches = @(
            foreach ($Argument in $Arguments) {

                foreach ($Pattern in $Patterns[$Category]) {

                    if ($Argument -like $Pattern) {

                        $Argument.Trim()
                        break
                    }
                }
            }
        ) | Select-Object -Unique


        foreach ($Match in $Matches) {

            $Results += [PSCustomObject]@{
                PID      = $ProcessID
                Started  = $Started
                Runtime  = $RuntimeText
                Detected = $ScanTime
                Category = $Category
                Details  = $Match
            }
        }
    }



    #
    # Classpath summary (separate section)
    #

    $ClasspathArg = $Arguments | Where-Object {
        $_ -like "-cp*" -or $_ -like "-classpath*"
    } | Select-Object -First 1


    if ($ClasspathArg) {

        $Classpath = $ClasspathArg `
            -replace '^-cp\s+', '' `
            -replace '^-classpath\s+', ''


        $Entries = $Classpath -split ';' | Where-Object { $_ }


        $MinecraftEntries = $Entries | Where-Object {
            $_ -match '\\libraries\\' -or
            $_ -match '\\versions\\'
        }


        $ExternalEntries = $Entries | Where-Object {
            $_ -notin $MinecraftEntries
        }


        $ClasspathResults += [PSCustomObject]@{
            PID       = $ProcessID
            Started   = $Started
            Entries   = $Entries.Count
            Minecraft = $MinecraftEntries.Count
            External  = $ExternalEntries.Count
        }


        foreach ($Entry in $ExternalEntries) {

            $ClasspathResults += [PSCustomObject]@{
                PID       = $ProcessID
                Started   = ""
                Entries   = ""
                Minecraft = ""
                External  = "! " + (Split-Path $Entry -Leaf)
            }
        }
    }



    #
    # External JAR Detection
    #

    $ExternalJars = @(
        foreach ($Argument in $Arguments) {

            if (
                $Argument -match '\.jar' -and
                $Argument -notmatch '\\mods\\' -and
                $Argument -notmatch '\\libraries\\'
            ) {

                $Argument.Trim()
            }
        }
    ) | Select-Object -Unique


    foreach ($Jar in $ExternalJars) {

        $Results += [PSCustomObject]@{
            PID      = $ProcessID
            Started  = $Started
            Runtime  = $RuntimeText
            Detected = $ScanTime
            Category = "External JAR"
            Details  = $Jar
        }
    }



    #
    # Duplicate Memory Checks
    #

    $Xmx = $Arguments | Where-Object { $_ -like "-Xmx*" }
    $Xms = $Arguments | Where-Object { $_ -like "-Xms*" }


    if ($Xmx.Count -gt 1) {

        $Results += [PSCustomObject]@{
            PID      = $ProcessID
            Started  = $Started
            Runtime  = $RuntimeText
            Detected = $ScanTime
            Category = "Warning"
            Details  = "Multiple -Xmx arguments detected"
        }
    }


    if ($Xms.Count -gt 1) {

        $Results += [PSCustomObject]@{
            PID      = $ProcessID
            Started  = $Started
            Runtime  = $RuntimeText
            Detected = $ScanTime
            Category = "Warning"
            Details  = "Multiple -Xms arguments detected"
        }
    }
}



#
# Output
#

# Increase console width so paths are not shortened
$host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(500,3000)

Write-Host ""
Write-Host "Acoustic is NOT a femboy" -ForegroundColor White
Write-Host ""

$Results |
    Sort-Object PID, Category |
    Format-Table `
        PID,
        Started,
        Runtime,
        Detected,
        Category,
        @{Name="Details"; Expression={$_.Details}; Width=250} `
        -Wrap



if ($ClasspathResults.Count -gt 0) {

    Write-Host ""
    Write-Host "Classpath summary" -ForegroundColor White
    Write-Host "-----------------" -ForegroundColor White
    Write-Host ""

    $ClasspathResults |
        Format-Table `
            PID,
            Started,
            Entries,
            Minecraft,
            @{Name="External"; Expression={$_.External}; Width=250} `
            -Wrap
}