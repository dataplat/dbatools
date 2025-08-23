function Repair-DbaInstanceName {
    <#
    .SYNOPSIS
        Updates SQL Server's @@SERVERNAME system variable to match the Windows hostname

    .DESCRIPTION
        Updates SQL Server's @@SERVERNAME system variable to match the current Windows hostname, which is required after renaming a Windows server. This ensures proper functionality for Kerberos authentication and Availability Groups.

        The function automatically detects the correct new server name and uses sp_dropserver and sp_addserver to update the SQL Server system tables. It handles common blockers like active replication and database mirroring, optionally removing them with the -AutoFix parameter.

        A SQL Server service restart is required to complete the rename process, which the function can perform automatically. The function will skip the operation if the names already match.

        https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AutoFix
        Automatically resolves blockers that prevent the server name repair, including removing replication distribution and disabling database mirroring.
        Use this when you need to fix the server name without manual intervention to remove these blocking configurations.
        This parameter will prompt for confirmation before breaking replication or mirroring unless combined with -Force.

    .PARAMETER Force
        Bypasses confirmation prompts for potentially destructive operations like stopping SQL services and breaking replication or mirroring.
        Use this for unattended automation or when you're certain about proceeding with all changes.
        Combine with -AutoFix for fully automated server name repairs without any prompts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SPN, Instance, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Repair-DbaInstanceName

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014

        Checks to see if the server name is updatable and changes the name with a number of prompts.

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014 -AutoFix

        Checks to see if the server name is updatable and automatically performs the change. Replication or mirroring will be broken if necessary.

    .EXAMPLE
        PS C:\> Repair-DbaInstanceName -SqlInstance sql2014 -AutoFix -Force

        Checks to see if the server name is updatable and automatically performs the change, bypassing most prompts and confirmations. Replication or mirroring will be broken if necessary.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$AutoFix,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.isClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Microsoft does not support renaming clusters."
                continue
            }


            # Check to see if we can easily proceed

            $nametest = Test-DbaInstanceName -SqlInstance $server
            $oldServerName = $nametest.ServerName
            $newServerName = $nametest.NewServerName

            if ($nametest.RenameRequired -eq $false) {
                Stop-Function -Continue -Message "Good news! $oldServerName's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
            }

            if (-not $nametest.Updatable) {
                Write-Message -Level Output -Message "Test-DbaInstanceName reports that the rename cannot proceed with a rename in this $instance's current state."

                foreach ($nametesterror in $nametest.Blockers) {
                    if ($nametesterror -like '*replication*') {

                        if (-not $AutoFix) {
                            Stop-Function -Message "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also break all database mirrors."
                            return
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: replication."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Stop-Function -Message "Failure" -Target $server -Continue
                                } else {
                                    Write-Message -Level Output -Message "`nPerforming sp_dropdistributor @no_checks = 1."
                                    $sql = "sp_dropdistributor @no_checks = 1"
                                    Write-Message -Level Debug -Message $sql
                                    try {
                                        $null = $server.Query($sql)
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
                                    }
                                }
                            }
                        }
                    } elseif ($Error -like '*mirror*') {
                        if ($AutoFix -eq $false) {
                            Stop-Function -Message "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also stop replication." -Continue
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: mirroring."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Write-Message -Level Output -Message "Okay, moving on."
                                } else {
                                    Write-Message -Level Verbose -Message "Removing Mirroring"

                                    foreach ($database in $server.Databases) {
                                        if ($database.IsMirroringEnabled) {
                                            $dbName = $database.name

                                            try {
                                                Write-Message -Level Verbose -Message "Breaking mirror for $dbName."
                                                $database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                                                $database.Alter()
                                                $database.Refresh()
                                            } catch {
                                                Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                                                return
                                                #throw "Could not break mirror for $dbName. Skipping."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # ^ That's embarrassing

            $instanceName = $server.InstanceName

            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }

            try {
                $allsqlservices = Get-Service -ComputerName $instance.ComputerName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instanceName*" -and $_.Status -eq "Running" }
            } catch {
                Write-Message -Level Warning -Message "Can't contact $instance using Get-Service. This means the script will not be able to automatically restart SQL services."
            }

            if ($nametest.Warnings -ne 'N/A') {
                $reportingservice = Get-Service -ComputerName $instance.ComputerName -DisplayName "SQL Server Reporting Services ($instanceName)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Message -Level Warning -Message "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $oldServerName, then sp_addserver to add $newServerName")) {
                $sql = "sp_dropserver '$oldServerName'"
                Write-Message -Level Debug -Message $sql
                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                    return
                }

                $sql = "sp_addserver '$newServerName', local"
                Write-Message -Level Debug -Message $sql

                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                    return
                }
                $renamed = $true
            }

            if ($null -eq $allsqlservices) {
                Write-Message -Level Warning -Message "Could not contact $($instance.ComputerName) using Get-Service. You must manually restart the SQL Server instance."
                $needsrestart = $true
            } else {
                if ($Pscmdlet.ShouldProcess($instance.ComputerName, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instanceName instance now?")) {
                    try {
                        Write-Message -Level Verbose -Message "Stopping SQL Services for the $instanceName instance"
                        $allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
                        Write-Message -Level Verbose -Message "Starting SQL Services for the $instanceName instance."
                        $allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
                    } catch {
                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
                    }
                }
            }

            if ($renamed -eq $true) {
                Write-Message -Level Verbose -Message "$instance successfully renamed from $oldServerName to $newServerName."
                Test-DbaInstanceName -SqlInstance $instance -SqlCredential $SqlCredential
            }

            if ($needsrestart -eq $true) {
                Write-Message -Level Warning -Message "SQL Service restart for $newServerName still required."
            }
        }
    }
}