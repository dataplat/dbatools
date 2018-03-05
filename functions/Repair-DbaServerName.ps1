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
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

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
        [switch]$Force,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        if ($Force -eq $true) {
            $ConfirmPreference = "None"
        }
    }

    process {
        foreach ($servername in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $servername"
            try {
                $server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $servername -Continue
            }

            if ($server.isClustered) {

                Write-Message -Level Warning -Message "$servername is a cluster. Microsoft does not support renaming clusters."
                Continue
            }


            # Check to see if we can easily proceed

            $nametest = Test-DbaServerName $servername -EnableException | Select-Object *
            $serverinstancename = $nametest.ServerInstanceName
            $SqlInstancename = $nametest.SqlServerName

            if ($nametest.RenameRequired -eq $false) {
                return "Good news! $serverinstancename's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server."
            }

            if ($nametest.updatable -eq $false) {
                Write-Message -Level Output -Message "Test-DbaServerName reports that the rename cannot proceed with a rename in this $servername's current state."

                $nametest

                foreach ($nametesterror in $nametest.Blockers) {
                    if ($nametesterror -like '*replication*') {

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
                                    Write-Message -Level Output -Message "`nPerforming sp_dropdistributor @no_checks = 1."
                                    $sql = "sp_dropdistributor @no_checks = 1"
                                    Write-Message -Level Debug -Message $sql
                                    try {
                                        $null = $server.Query($sql)
                                    }
                                    catch {
                                        Stop-Function -Message "Failure" -Target $server -Error $_ -Exception $_.Exception.InnerException
                                        return
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
                                    Write-Message -Level Output -Message "Okay, moving on."
                                }
                                else {
                                    Write-Message -Level Verbose -Message "Removing Mirroring"

                                    foreach ($database in $server.Databases) {
                                        if ($database.IsMirroringEnabled) {
                                            $dbname = $database.name

                                            try {
                                                Write-Message -Level Verbose -Message "Breaking mirror for $dbname."
                                                $database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                                                $database.Alter()
                                                $database.Refresh()
                                            }
                                            catch {
                                                Stop-Function -Message "Failure" -Target $server -Error $_ -Exception $_.Exception.InnerException
                                                return
                                                #throw "Could not break mirror for $dbname. Skipping."
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
                Write-Message -Level Warning -Message "Can't contact $servername using Get-Service. This means the script will not be able to automatically restart SQL services."
            }

            if ($nametest.Warnings.length -gt 0) {
                $reportingservice = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -DisplayName "SQL Server Reporting Services ($instance)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Message -Level Warning -Message "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $SqlInstancename, then sp_addserver to add $serverinstancename")) {
                $sql = "sp_dropserver '$SqlInstancename'"
                Write-Message -Level Debug -Message $sql
                try {
                    $null = $server.Query($sql)
                }
                catch {
                    Stop-Function -Message "Failure" -Target $server -Error $_ -Exception $_.Exception.InnerException
                    return
                }

                $sql = "sp_addserver '$serverinstancename', local"
                Write-Message -Level Debug -Message $sql

                try {
                    $null = $server.Query($sql)
                }
                catch {
                    Stop-Function -Message "Failure" -Target $server -Error $_ -Exception $_.Exception.InnerException
                    return
                }
                $renamed = $true
            }

            if ($null -eq $allsqlservices) {
                Write-Message -Level Warning -Message "Could not contact $($server.ComputerNamePhysicalNetBIOS) using Get-Service. You must manually restart the SQL Server instance."
                $needsrestart = $true
            }
            else {
                if ($Pscmdlet.ShouldProcess($server.ComputerNamePhysicalNetBIOS, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instancename instance now?")) {
                    try {
                        Write-Message -Level Verbose -Message "Stopping SQL Services for the $instancename instance"
                        $allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
                        Write-Message -Level Verbose -Message "Starting SQL Services for the $instancename instance."
                        $allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
                    }
                    catch {
                        Stop-Function -Message "Failure" -Target $server -Error $_ -Exception $_.Exception.InnerException
                        throw "Could not restart at least one SQL Service."
                    }
                }
            }

            if ($renamed -eq $true) {
                Write-Message -Level Output -Message "$servername successfully renamed from $SqlInstancename to $serverinstancename."
            }

            if ($needsrestart -eq $true) {
                Write-Message -Level Output -Message "SQL Service restart for $serverinstancename still required."
            }
        }
    }
}