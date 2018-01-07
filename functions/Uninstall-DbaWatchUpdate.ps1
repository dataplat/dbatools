function Uninstall-DbaWatchUpdate {
    <#
        .SYNOPSIS
            Removes the scheduled task created for Watch-DbaUpdate by Install-DbaWatchUpdate so that notifications no longer pop up.

        .DESCRIPTION
            Removes the scheduled task created for Watch-DbaUpdate by Install-DbaWatchUpdate so that notifications no longer pop up.

        .NOTES
            Tags: JustForFun, Module
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Uninstall-DbaWatchUpdate

        .EXAMPLE
            Uninstall-DbaWatchUpdate

            Removes the scheduled task created by Install-DbaWatchUpdate.
    #>
    process {
        if (([Environment]::OSVersion).Version.Major -lt 10) {
            Write-Warning "This command only supports Windows 10 and higher."
            return
        }

        <# Does not utilize message system because of script block #>
        $script = {
            try {
                $task = Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue

                if ($null -eq $task) {
                    Write-Warning "Task doesn't exist. Skipping removal."
                }
                else {
                    Write-Output "Removing watchupdate.xml."
                    $file = "$env:LOCALAPPDATA\dbatools\watchupdate.xml"
                    Remove-Item $file -ErrorAction SilentlyContinue

                    Write-Output "Removing Scheduled Task 'dbatools version check'."
                    $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop

                    Write-Output "Task removed"

                    Start-Sleep -Seconds 2
                }
            }
            catch {
                Write-Warning "Task could not be deleted. Please remove 'dbatools version check' manually."
            }
        }
        # Needs admin credentials to remove the task because of the way it was setup

        $task = Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue

        if ($null -eq $task) {
            Write-Warning "dbatools update watcher is not installed."
            return
        }

        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Warning "Removal of this scheduled task requires elevated permissions."
            Start-Process powershell -Verb runAs -ArgumentList Uninstall-DbaWatchUpdate -Wait
        }
        else {
            Invoke-Command -ScriptBlock $script
        }

        Write-Output "All done!"
    }
}
