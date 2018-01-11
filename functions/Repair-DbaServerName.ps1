function Repair-DbaServerName {
    <#
        .SYNOPSIS
            Renames @@SERVERNAME to match with the Windows name.

        .DESCRIPTION
            When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

            This command renames @@SERVERNAME to match with the Windows name. The new name is automatically determined. It does not matter if you use an alias to connect to the SQL instance.

            If the automatically determined new name matches the old name, the command will not run.

            https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER AutoFix
            If this switch is enabled, the repair will be performed automatically.

        .PARAMETER Force
            If this switch is enabled, most confirmation prompts will be skipped.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: SPN
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Repair-DbaServerName

        .EXAMPLE
            Repair-DbaServerName -SqlInstance sql2014

            Checks to see if the server name is updatable and changes the name with a number of prompts.

        .EXAMPLE
            Repair-DbaServerName -SqlInstance sql2014 -AutoFix

            Checks to see if the server name is updatable and automatically performs the change. Replication or mirroring will be broken if necessary.

        .EXAMPLE
            Repair-DbaServerName -SqlInstance sql2014 -AutoFix -Force

            Checks to see if the server name is updatable and automatically performs the change, bypassing most prompts and confirmations. Replication or mirroring will be broken if necessary.
    #>
    [OutputType("System.String")]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [switch]$AutoFix,
        [switch]$Force
    )

    begin {
        if ($Force -eq $true) {
            $ConfirmPreference = "None"
        }
    }

    process {
        foreach ($servername in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
            }
            catch {
                Write-Warning "Can't connect to $servername. Moving on."
                Continue
            }

            if ($server.isClustered) {

                Write-Warning "$servername is a cluster. Microsoft does not support renaming clusters."
                Continue
            }

            if ($server.VersionMajor -eq 8) {
                Write-Warning "SQL Server 2000 not supported. Skipping $servername."
                Continue
            }

            # Check to see if we can easily proceed
            Write-Verbose "Executing Test-DbaServerName to see if the server is in a state to be renamed. "

            $nametest = Test-DbaServerName $servername -NoWarning | Select-Object *
            $serverinstancename = $nametest.ServerInstanceName
            $SqlInstancename = $nametest.SqlServerName

            if ($nametest.RenameRequired -eq $false) {
                return "Good news! $serverinstancename's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
            }

            if ($nametest.updatable -eq $false) {
                Write-Output "Test-DbaServerName reports that the rename cannot proceed with a rename in this $servername's current state."

                $nametest

                foreach ($nametesterror in $nametest.Blockers) {
                    if ($nametesterror -like '*replication*') {
                        $replication = $true

                        if ($AutoFix -eq $false) {
                            throw "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also break all database mirrors."
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: replication."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    throw "Cannot continue"
                                }
                                else {
                                    Write-Output "`nPerforming sp_dropdistributor @no_checks = 1."
                                    $sql = "sp_dropdistributor @no_checks = 1"
                                    Write-Debug $sql
                                    try {
                                        $null = $server.Query($sql)
                                        Write-Output "Successfully executed $sql.`n"
                                    }
                                    catch {
                                        Write-Exception $_
                                        throw $_
                                    }
                                }
                            }
                        }
                    }
                    elseif ($Error -like '*mirror*') {
                        if ($AutoFix -eq $false) {
                            throw "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also stop replication."
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: mirroring."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Write-Output "Okay, moving on."
                                }
                                else {
                                    Write-Output "Removing Mirroring"

                                    foreach ($database in $server.Databases) {
                                        if ($database.IsMirroringEnabled) {
                                            $dbname = $database.name

                                            try {
                                                Write-Output "Breaking mirror for $dbname."
                                                $database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                                                $database.Alter()
                                                $database.Refresh()
                                            }
                                            catch {
                                                Write-Exception $_
                                                throw "Could not break mirror for $dbname. Skipping."
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

            $instancename = $instance = $server.InstanceName

            if ($instancename.length -eq 0) {
                $instancename = $instance = "MSSQLSERVER"
            }

            try {
                $allsqlservices = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instance*" -and $_.Status -eq "Running" }
            }
            catch {
                Write-Warning "Can't contact $servername using Get-Service. This means the script will not be able to automatically restart SQL services."
            }

            if ($nametest.Warnings.length -gt 0) {
                $reportingservice = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -DisplayName "SQL Server Reporting Services ($instance)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Warning "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $SqlInstancename, then sp_addserver to add $serverinstancename")) {
                $sql = "sp_dropserver '$SqlInstancename'"
                Write-Debug $sql
                try {
                    $null = $server.Query($sql)
                    Write-Output "`nSuccessfully executed $sql."
                }
                catch {
                    Write-Exception $_
                    throw $_
                }

                $sql = "sp_addserver '$serverinstancename', local"
                Write-Debug $sql

                try {
                    $null = $server.Query($sql)
                    Write-Output "Successfully executed $sql."
                }
                catch {
                    Write-Exception $_
                    throw $_
                }
                $renamed = $true
            }

            if ($allsqlservices -eq $null) {
                Write-Warning "Could not contact $($server.ComputerNamePhysicalNetBIOS) using Get-Service. You must manually restart the SQL Server instance."
                $needsrestart = $true
            }
            else {
                if ($Pscmdlet.ShouldProcess($server.ComputerNamePhysicalNetBIOS, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instancename instance now?")) {
                    try {
                        Write-Output "`nStopping SQL Services for the $instancename instance"
                        $allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
                        Write-Output "Starting SQL Services for the $instancename instance."
                        $allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
                    }
                    catch {
                        Write-Exception $_
                        throw "Could not restart at least one SQL Service."
                    }
                }
            }

            if ($renamed -eq $true) {
                Write-Output "`n$servername successfully renamed from $SqlInstancename to $serverinstancename."
            }

            if ($needsrestart -eq $true) {
                Write-Output "SQL Service restart for $serverinstancename still required."
            }
        }
    }
}