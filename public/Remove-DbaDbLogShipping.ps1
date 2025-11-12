<#
    .SYNOPSIS
        Dismantles SQL Server log shipping configurations and removes associated jobs and monitoring

    .DESCRIPTION
        Completely removes log shipping setup from both primary and secondary instances by cleaning up all associated SQL Agent jobs, monitor configurations, and database relationships stored in msdb. This function calls the proper SQL Server system stored procedures (sp_delete_log_shipping_primary_secondary, sp_delete_log_shipping_primary_database, and sp_delete_log_shipping_secondary_database) to ensure clean removal without orphaned objects.

        Use this when migrating to different disaster recovery solutions, cleaning up failed log shipping setups, or decommissioning secondary servers. The function automatically discovers secondary server information from the log shipping configuration if not specified.

        By default, the secondary database remains intact and accessible after log shipping removal. Use -RemoveSecondaryDatabase to completely drop the secondary database as part of the cleanup process.

    .PARAMETER PrimarySqlInstance
        The SQL Server instance hosting the primary database(s) in the log shipping configuration. This server contains the source database that is being shipped to secondary instances.
        You must have sysadmin access to execute the log shipping removal stored procedures. Requires SQL Server 2000 or later.

    .PARAMETER SecondarySqlInstance
        The SQL Server instance hosting the secondary database(s) in the log shipping configuration. If not specified, the function automatically discovers this from the log shipping metadata in msdb.
        Required when removing log shipping from multiple secondary instances or when automatic discovery fails. You must have sysadmin access to clean up secondary database configurations.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The primary database name(s) to remove from log shipping configuration. Accepts multiple databases via pipeline or array input.
        Must specify the database name as it exists on the primary instance, not the secondary instance name which may be different.

    .PARAMETER RemoveSecondaryDatabase
        Completely drops the secondary database from the secondary instance after removing the log shipping configuration. By default, the secondary database remains intact and accessible.
        Use this when decommissioning the secondary server or when you need to start fresh with a new log shipping setup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbLogShipping

    .EXAMPLE
        Remove-DbaDbLogShipping -PrimarySqlInstance sql1 -SecondarySqlInstance sql2 -Database DB1

        Remove the log shipping for database DB1

    .EXAMPLE
        Remove-DbaDbLogShipping -PrimarySqlInstance sql1 -Database DB1

        Remove the log shipping for database DB1 and let the command figure out the secondary instance

    .EXAMPLE
        Remove-DbaDbLogShipping -PrimarySqlInstance localhost -SecondarySqlInstance sql2 -Database DB1, DB2

        Remove the log shipping for multiple database

    .EXAMPLE
        Remove-DbaDbLogShipping -PrimarySqlInstance localhost -SecondarySqlInstance localhost -Database DB2 -RemoveSecondaryDatabase

        Remove the log shipping for database DB2 and remove the database from the secondary instance


    #>
function Remove-DbaDbLogShipping {

    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]

    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$PrimarySqlInstance,
        [DbaInstanceParameter]$SecondarySqlInstance,
        [System.Management.Automation.PSCredential]
        $PrimarySqlCredential,
        [System.Management.Automation.PSCredential]
        $SecondarySqlCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Database,
        [switch]$RemoveSecondaryDatabase,
        [switch]$EnableException
    )

    begin {
        if (-not $Database) {
            Stop-Function -Message "Please enter one or more databases"
        }

        # Try connecting to the source instance
        try {
            $primaryServer = Connect-DbaInstance -SqlInstance $PrimarySqlInstance -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $PrimarySqlInstance
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($db in $Database) {
            if ($db -notin $primaryServer.Databases.Name) {
                Stop-Function -Message "Database [$db] does not exists on $primaryServer" -Target $db -Continue
            }

            # Get the log shipping information
            $query = "SELECT pd.primary_database AS PrimaryDatabase,
                    ps.secondary_server AS SecondaryServer,
                    ps.secondary_database AS SecondaryDatabase
                FROM msdb.dbo.log_shipping_primary_secondaries AS ps
                    INNER JOIN msdb.dbo.log_shipping_primary_databases AS pd
                        ON [pd].[primary_id] = [ps].[primary_id]
                WHERE pd.[primary_database] = '$db';"

            try {
                [array]$logshippingInfo = Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database msdb -Query $query
            } catch {
                Stop-Function -Message "Something went wrong retrieving the log shipping information" -Target $primaryServer -ErrorRecord $_
            }

            if ($logshippingInfo.Count -lt 1) {
                Stop-Function -Message "Could not retrieve log shipping information for [$db]" -Target $db -Continue
            }

            # Get the secondary server if it's not set
            if (-not $SecondarySqlInstance) {
                $SecondarySqlInstance = $logshippingInfo.SecondaryServer
            }

            # Try connecting to the destination instance
            try {
                $secondaryServer = Connect-DbaInstance -SqlInstance $SecondarySqlInstance -SqlCredential $SecondarySqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SecondarySqlInstance
                return
            }

            # Remove the primary secondaries log shipping
            if ($PSCmdlet.ShouldProcess("Removing the primary and secondaries from log shipping")) {
                $query = "EXEC dbo.sp_delete_log_shipping_primary_secondary
                    @primary_database = N'$($logshippingInfo.PrimaryDatabase)',
                    @secondary_server = N'$($logshippingInfo.SecondaryServer)',
                    @secondary_database = N'$($logshippingInfo.SecondaryDatabase)'"

                try {
                    Write-Message -Level verbose -Message "Removing the primary and secondaries from log shipping"
                    Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database master -Query $query
                } catch {
                    Stop-Function -Message "Something went wrong removing the primaries and secondaries" -Target $primaryServer -ErrorRecord $_
                }
            }

            # Remove the primary database log shipping info
            if ($PSCmdlet.ShouldProcess("Removing the primary database from log shipping")) {
                $query = "EXEC dbo.sp_delete_log_shipping_primary_database @database = N'$($logshippingInfo.PrimaryDatabase)'"

                try {
                    Write-Message -Level verbose -Message "Removing the primary database from log shipping"
                    Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database master -Query $query
                } catch {
                    Stop-Function -Message "Something went wrong removing the primary database from log shipping" -Target $primaryServer -ErrorRecord $_
                }
            }

            # Remove the secondary database log shipping
            if ($PSCmdlet.ShouldProcess("Removing the secondary database from log shipping")) {
                $query = "EXEC dbo.sp_delete_log_shipping_secondary_database @secondary_database = N'$($logshippingInfo.SecondaryDatabase)'"

                try {
                    Write-Message -Level verbose -Message "Removing the secondary database from log shipping"
                    Invoke-DbaQuery -SqlInstance $secondaryServer -SqlCredential $SecondarySqlCredential -Database master -Query $query
                } catch {
                    Stop-Function -Message "Something went wrong removing the secondary database from log shipping" -Target $secondaryServer -ErrorRecord $_
                }
            }

            # Remove the secondary database if needed
            if ($RemoveSecondaryDatabase) {
                if ($PSCmdlet.ShouldProcess("Removing the secondary database from [$($logshippingInfo.SecondaryDatabase)]")) {
                    Write-Message -Level verbose -Message "Removing the secondary database [$($logshippingInfo.SecondaryDatabase)]"
                    try {
                        $null = Remove-DbaDatabase -SqlInstance $secondaryServer -SqlCredential $SecondarySqlCredential -Database $logshippingInfo.SecondaryDatabase -Confirm:$false
                    } catch {
                        Stop-Function -Message "Could not remove [$($logshippingInfo.SecondaryDatabase)] from $secondaryServer" -Target $secondaryServer -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}