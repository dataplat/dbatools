function Uninstall-DbatoolsWatchUpdate {
    <#
    .SYNOPSIS
        Removes the scheduled task created for Watch-DbaUpdate by Install-DbatoolsWatchUpdate so that notifications no longer pop up.

    .DESCRIPTION
        Removes the scheduled task created for Watch-DbaUpdate by Install-DbatoolsWatchUpdate so that notifications no longer pop up.

    .NOTES
        Tags: Module, Watcher
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Uninstall-DbatoolsWatchUpdate

    .EXAMPLE
        PS C:\> Uninstall-DbatoolsWatchUpdate

        Removes the scheduled task created by Install-DbatoolsWatchUpdate.
    #>
    [Cmdletbinding()]
    param()
    process {
        if (([Environment]::OSVersion).Version.Major -lt 10) {
            Write-Message -Level Warning -Message "This command only supports Windows 10 and higher."
            return
        }

        <# Does not utilize message system because of script block #>
        $script = {
            try {
                $task = Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue

                if ($null -eq $task) {
                    Write-Message -Level Warning -Message "Task doesn't exist. Skipping removal."
                } else {
                    Write-Message -Level Output -Message "Removing watchupdate.xml."
                    $file = "$(Get-DbatoolsPath -Name localappdata)\dbatools\watchupdate.xml"
                    Remove-Item $file -ErrorAction SilentlyContinue

                    Write-Message -Level Output -Message "Removing Scheduled Task 'dbatools version check'."
                    $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop

                    Write-Message -Level Output -Message "Task removed"

                    Start-Sleep -Seconds 2
                }
            } catch {
                Write-Message -Level Warning -Message "Task could not be deleted. Please remove 'dbatools version check' manually."
            }
        }
        # Needs admin credentials to remove the task because of the way it was setup

        $task = Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue

        if ($null -eq $task) {
            Write-Message -Level Warning -Message "dbatools update watcher is not installed."
            return
        }

        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Message -Level Warning -Message "Removal of this scheduled task requires elevated permissions."
            Start-Process powershell -Verb runAs -ArgumentList Uninstall-DbatoolsWatchUpdate -Wait
        } else {
            Invoke-Command -ScriptBlock $script
        }

        Write-Message -Level Output -Message "All done."
    }
}