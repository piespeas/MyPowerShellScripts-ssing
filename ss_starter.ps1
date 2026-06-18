#Requires -RunAsAdministrator

function Start-PersistentScript {
    param (
        [string]$Url
    )

    $command = "powershell -NoExit -ExecutionPolicy Bypass -Command `"try { iex (irm '$Url') } catch { Write-Host `$_ -ForegroundColor Red }; Write-Host ''; Write-Host 'Keeping window open... Do NOT close the CMD window, all progress will be lost' -ForegroundColor Cyan; while (`$true) { Start-Sleep 3600 }`""

    Start-Process cmd.exe -Verb RunAs -ArgumentList "/k $command"
}

# -----------------------
# Launch scripts
# -----------------------

Start-PersistentScript "https://raw.githubusercontent.com/piespeas/MyPowerShellScripts-ssing/refs/heads/main/Screenshare.ps1"

Start-PersistentScript "https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/Signed-Scheduled-Tasks"

Start-PersistentScript "https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/DoomsdayFinder.ps1"

Start-PersistentScript "https://raw.githubusercontent.com/Enr1c0o/Powershell-Scripts/refs/heads/main/Alt-Detector.ps1"

Start-PersistentScript "https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/ShellSearch.ps1"

Start-PersistentScript "https://raw.githubusercontent.com/praiselily/lilith-ps/refs/heads/main/CommonDirectories.ps1"

Start-PersistentScript "https://raw.githubusercontent.com/PureIntent/ScreenShare/main/RedLotusBam.ps1"




# -----------------------
# Open folders
# -----------------------

Start-Process explorer.exe $env:TEMP
Start-Process explorer.exe "shell:recent"

Write-Host "Meow!!!." -ForegroundColor Red
