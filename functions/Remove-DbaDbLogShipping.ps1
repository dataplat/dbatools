<#
    .SYNOPSIS
        Remove-DbaDbLogShipping will remove one or more databases from log shipping

    .DESCRIPTION
        The command Remove-DbaDbLogShipping will remove one or more databases from log shipping

        After running the command it will remove all the jobs, configurations set up for log shipping

        By default the secondary database will NOT be removed.
        Use -RemoveSecondaryDatabase to make the command the secondary database

    .PARAMETER PrimarySqlInstance
        Primary SQL Server instance which contains the primary database(s).
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SecondarySqlInstance
        Secondary SQL Server instance which contains the secondary database(s)
        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Database to remove from log shipping.

        This is the name of the database located on the primary instance

    .PARAMETER RemoveSecondaryDatabase
        By default the command will not remove the database from the secondary instance.
        Use this parameter to make the command remove that database

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        Use this switch to disable any kind of verbose messages

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
            $primaryServer = Connect-SqlInstance -SqlInstance $PrimarySqlInstance -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Could not connect to Sql Server instance $PrimarySqlInstance" -ErrorRecord $_ -Target $PrimarySqlInstance
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
                $secondaryServer = Connect-SqlInstance -SqlInstance $SecondarySqlInstance -SqlCredential $SecondarySqlCredential
            } catch {
                Stop-Function -Message "Could not connect to Sql Server instance $SecondarySqlInstance" -ErrorRecord $_ -Target $SecondarySqlInstance
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
                $query = "EXEC sp_delete_log_shipping_primary_database @database = N'$($logshippingInfo.PrimaryDatabase)'"

                try {
                    Write-Message -Level verbose -Message "Removing the primary database from log shipping"
                    Invoke-DbaQuery -SqlInstance $primaryServer -SqlCredential $PrimarySqlCredential -Database master -Query $query
                } catch {
                    Stop-Function -Message "Something went wrong removing the primary database from log shipping" -Target $primaryServer -ErrorRecord $_
                }
            }

            # Remove the secondary database log shipping
            if ($PSCmdlet.ShouldProcess("Removing the secondary database from log shipping")) {
                $query = "EXEC sp_delete_log_shipping_secondary_database @secondary_database = N'$($logshippingInfo.SecondaryDatabase)'"

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