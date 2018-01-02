function Install-DbaWatchUpdate {
    <#
        .SYNOPSIS
            Adds the scheduled task to support Watch-DbaUpdate.

        .DESCRIPTION
            Adds the scheduled task to support Watch-DbaUpdate.

        .NOTES
            Tags: JustForFun, Module
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Install-DbaWatchUpdate

        .EXAMPLE
            Install-DbaWatchUpdate

            Adds the scheduled task needed by Watch-DbaUpdate
    #>
    process {
        if (([Environment]::OSVersion).Version.Major -lt 10) {
            Write-Warning "This command only supports Windows 10 and above"
            return
        }

        $script = {
            try {
                # create a task, check every 3 hours
                $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden Watch-DbaUpdate'
                $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
                $principal = New-ScheduledTaskPrincipal -LogonType S4U -UserId (whoami)
                $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
                $task = Register-ScheduledTask -Principal $principal -TaskName 'dbatools version check' -Action $action -Trigger $trigger -Settings $settings -ErrorAction Stop
            }
            catch {
                # keep moving
            }
        }

        if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue)) {
            # Needs admin creds to setup the kind of PowerShell window that doesn't appear for a millisecond
            # which is a millisecond too long
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                Write-Warning "Watch-DbaUpdate runs as a Scheduled Task which must be created. This will only happen once."
                Start-Process powershell -Verb runAs -ArgumentList Install-DbaWatchUpdate -Wait
            }

            try {
                Invoke-Command -ScriptBlock $script -ErrorAction Stop

                if ((Get-Location).Path -ne "$env:windir\system32") {
                    $module = Get-Module -Name dbatools
                    Write-Warning "Task created! A notification should appear momentarily. Here's something cute to look at in the interim."
                    Show-Notification -Title "dbatools wants you" -Text "come hang out at dbatools.io/slack"
                }
            }
            catch {
                Write-Warning "Couldn't create scheduled task :("
                return
            }

            # doublecheck
            if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue)) {
                Write-Warning "Couldn't create scheduled task."
            }
        }
        else {
            Write-Output "Watch-DbaUpdate is already installed as a scheduled task called 'dbatools version check'"
        }
    }
}
