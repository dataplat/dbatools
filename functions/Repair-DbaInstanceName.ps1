function Repair-DbaInstanceName {
    <#
    .SYNOPSIS
        Renames @@SERVERNAME to match with the Windows name.

    .DESCRIPTION
        When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

        This command renames @@SERVERNAME to match with the Windows name. The new name is automatically determined. It does not matter if you use an alias to connect to the SQL instance.

        If the automatically determined new name matches the old name, the command will not run.

        https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AutoFix
        If this switch is enabled, the repair will be performed automatically.

    .PARAMETER Force
        If this switch is enabled, most confirmation prompts will be skipped.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SPN
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.isClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Microsoft does not support renaming clusters."
                continue
            }


            # Check to see if we can easily proceed

            $nametest = Test-DbaInstanceName $server -EnableException | Select-Object *
            $oldserverinstancename = $nametest.ServerName
            $SqlInstancename = $nametest.SqlInstance

            if ($nametest.RenameRequired -eq $false) {
                Stop-Function -Continue -Message "Good news! $oldserverinstancename's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
            }

            if (-not $nametest.updatable) {
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
                                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue
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

            if ($nametest.Warnings.length -gt 0) {
                $reportingservice = Get-Service -ComputerName $instance.ComputerName -DisplayName "SQL Server Reporting Services ($instanceName)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Message -Level Warning -Message "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $oldserverinstancename, then sp_addserver to add $SqlInstancename")) {
                $sql = "sp_dropserver '$oldserverinstancename'"
                Write-Message -Level Debug -Message $sql
                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_
                    return
                }

                $sql = "sp_addserver '$SqlInstancename', local"
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
                Write-Message -Level Verbose -Message "$instance successfully renamed from $oldserverinstancename to $SqlInstancename."
                Test-DbaInstanceName -SqlInstance $server
            }

            if ($needsrestart -eq $true) {
                Write-Message -Level Warning -Message "SQL Service restart for $SqlInstancename still required."
            }
        }
    }
}