function New-DbaLogShippingPrimarySecondary {
    <#
        .SYNOPSIS
            New-DbaLogShippingPrimarySecondary adds an entry for a secondary database.

        .DESCRIPTION
            New-DbaLogShippingPrimarySecondary adds an entry for a secondary database.
            This is executed on the primary server.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER PrimaryDatabase
            Is the name of the database on the primary server.

        .PARAMETER SecondaryDatabase
            Is the name of the secondary database.

        .PARAMETER SecondaryServer
            Is the name of the secondary server.

        .PARAMETER SecondarySqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
            $scred = Get-Credential, then pass $scred object to the -SecondarySqlCredential parameter.

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/New-DbaLogShippingPrimarySecondary

        .EXAMPLE
            New-DbaLogShippingPrimarySecondary -SqlInstance sql1 -PrimaryDatabase DB1 -SecondaryServer sql2 -SecondaryDatabase DB1_DR
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$PrimaryDatabase,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SecondaryDatabase,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DBAInstanceParameter]$SecondaryServer,
        [PSCredential]$SecondarySqlCredential,
        [switch]$EnableException
    )

    # Try connecting to the instance
    try {
        $ServerPrimary = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SqlInstance -Continue
    }

    # Try connecting to the instance
    try {
        $ServerSecondary = Connect-SqlInstance -SqlInstance $SecondaryServer -SqlCredential $SecondarySqlCredential
    } catch {
        Stop-Function -Message "Could not connect to Sql Server instance" -Target $SecondaryServer -Continue
    }

    # Check if the database is present on the source sql server
    if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
        Stop-Function -Message "Database $PrimaryDatabase is not available on instance $SqlInstance" -ErrorRecord $_ -Target $SqlInstance -Continue
    }

    # Check if the database is present on the destination sql server
    if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
        Stop-Function -Message "Database $SecondaryDatabase is not available on instance $SecondaryServer" -ErrorRecord $_ -Target $SecondaryServer -Continue
    }

    $Query = "SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = '$PrimaryDatabase'"

    try {
        Write-Message -Message "Executing query:`n$Query" -Level Verbose
        $Result = $ServerPrimary.Query($Query)
        if ($Result.Count -eq 0 -or $Result[0] -ne $PrimaryDatabase) {
            Stop-Function -Message "Database $PrimaryDatabase does not exist as log shipping primary.`nPlease run New-DbaLogShippingPrimaryDatabase first."  -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    } catch {
        Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query" -ErrorRecord $_ -Target $SqlInstance -Continue
    }

    # Set the query for the log shipping primary and secondary
    $Query = "EXEC master.sys.sp_add_log_shipping_primary_secondary
        @primary_database = N'$PrimaryDatabase'
        ,@secondary_server = N'$SecondaryServer'
        ,@secondary_database = N'$SecondaryDatabase' "

    if ($ServerPrimary.Version.Major -gt 9) {
        $Query += ",@overwrite = 1;"
    } else {
        $Query += ";"
    }

    # Execute the query to add the log shipping primary
    if ($PSCmdlet.ShouldProcess($SqlInstance, ("Configuring logshipping connecting the primary database $PrimaryDatabase to secondary database $SecondaryDatabase on $SqlInstance"))) {
        try {
            Write-Message -Message "Configuring logshipping connecting the primary database $PrimaryDatabase to secondary database $SecondaryDatabase on $SqlInstance." -Level Verbose
            Write-Message -Message "Executing query:`n$Query" -Level Verbose
            $ServerPrimary.Query($Query)
        } catch {
            Write-Message -Message "$($_.Exception.InnerException.InnerException.InnerException.InnerException.Message)" -Level Warning
            Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query" -ErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    Write-Message -Message "Finished configuring of primary database $PrimaryDatabase to secondary database $SecondaryDatabase." -Level Verbose

}