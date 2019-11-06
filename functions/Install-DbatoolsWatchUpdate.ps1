function Install-DbatoolsWatchUpdate {
    <#
    .SYNOPSIS
        Adds the scheduled task to support Watch-DbaUpdate.

    .DESCRIPTION
        Adds the scheduled task to support Watch-DbaUpdate.

    .PARAMETER TaskName
        Provide custom name for the Scheduled Task

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, Watcher
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbatoolsWatchUpdate

    .EXAMPLE
        PS C:\> Install-DbatoolsWatchUpdate

        Adds the scheduled task needed by Watch-DbaUpdate

    .EXAMPLE
        PS C:\> Install-DbatoolsWatchUpdate -TaskName MyScheduledTask

        Will create the scheduled task as the name MyScheduledTask
    #>
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [string]$TaskName = 'dbatools version check',
        [switch]$EnableException
    )
    process {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Validate Version of OS") ) {
            if (([Environment]::OSVersion).Version.Major -lt 10) {
                Stop-Function -Message "This command only supports Windows 10 and above"
            }
        }
        $script = {
            try {
                # create a task, check every 3 hours
                $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden Watch-DbaUpdate'
                $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
                $principal = New-ScheduledTaskPrincipal -LogonType S4U -UserId (whoami)
                $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
                #Variable $Task marked as unused by PSScriptAnalyzer replaced with $null for catching output
                $null = Register-ScheduledTask -Principal $principal -TaskName 'dbatools version check' -Action $action -Trigger $trigger -Settings $settings -ErrorAction Stop
            } catch {
                # keep moving
                # here to avoid an empty catch
                $null = 1
            }
        }

        if ($null -eq (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
            # Needs admin creds to setup the kind of PowerShell window that doesn't appear for a millisecond
            # which is a millisecond too long
            if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Validate running in RunAs mode")) {
                if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                    Write-Message -Level Warning -Message "This command has to run using RunAs mode (privileged) to create the Scheduled Task. This will only happen once."
                    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Starting process in RunAs mode") ) {
                        Start-Process powershell -Verb runAs -ArgumentList Install-DbatoolsWatchUpdate -Wait
                    }
                }

            }
            if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Creating scheduled task $TaskName")) {
                try {
                    Invoke-Command -ScriptBlock $script -ErrorAction Stop

                    if ((Get-Location).Path -ne "$env:WINDIR\system32") {
                        Write-Message -Level Output -Message "Scheduled Task [$TaskName] created! A notification should appear momentarily. Here's something cute to look at in the interim."
                        Show-Notification -Title "dbatools wants you" -Text "come hang out at dbatools.io/slack"
                    }
                } catch {
                    Stop-Function -Message "Could not create scheduled task $TaskName" -Target $env:COMPUTERNAME -ErrorRecord $_
                }
            }
            if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Checking scheduled task was created")) {
                # double check
                if ($null -eq (Get-ScheduledTask -TaskName "dbatools version check" -ErrorAction SilentlyContinue)) {
                    Write-Message -Level Warning -Message "Scheduled Task was not created."
                }
            }
        } else {
            Write-Message -Level Output -Message "Scheduled Task $TaskName is already installed on this machine."
        }
    }
}