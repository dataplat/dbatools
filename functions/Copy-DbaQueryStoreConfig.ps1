function Copy-DbaQueryStoreConfig {
    <#
        .SYNOPSIS
            Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

        .DESCRIPTION
            Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2016 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER SourceDatabase
            Specifies the database to copy the Query Store configuration from.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2016 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER DestinationDatabase
            Specifies a list of databases that will receive a copy of the Query Store configuration of the SourceDatabase.

        .PARAMETER Exclude
            Specifies a list of databases which will NOT receive a copy of the Query Store configuration.

        .PARAMETER AllDatabases
            If this switch is enabled, the Query Store configuration will be copied to all databases on the destination instance.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Enrico van de Laar ( @evdlaar )
            Tags: QueryStore

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-QueryStoreConfig

        .EXAMPLE
            Copy-DbaQueryStoreConfig -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -AllDatabases

            Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it on all user databases in the ServerB\SQL Instance.

        .EXAMPLE
            Copy-DbaQueryStoreConfig -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -DestinationDatabase WorldWideTraders

            Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it to the WorldWideTraders database in the ServerB\SQL Instance.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$SourceDatabase,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$DestinationDatabase,
        [object[]]$Exclude,
        [switch]$AllDatabases,
        [switch][Alias('Silent')]$EnableException
    )

    BEGIN {

        Write-Message -Message "Connecting to source: $Source." -Level Verbose
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        }
        catch {
            Stop-Function -Message "Can't connect to $Source." -InnerErrorRecord $_ -Target $Source
        }
    }

    PROCESS {
        if (Test-FunctionInterrupt) {
            return
        }
        # Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
        $SourceQSConfig = Get-DbaQueryStoreConfig -SqlInstance $sourceServer -Database $SourceDatabase

        if (!$DestinationDatabase -and !$Exclude -and !$AllDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases." -Continue
        }

        foreach ($destinationServer in $Destination) {

            Write-Message -Message "Connecting to destination: $Destination." -Level Verbose
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinationServer -SqlCredential $DestinationSqlCredential
            }
            catch {
                Stop-Function -Message "Can't connect to $destinationServer." -InnerErrorRecord $_ -Target $destinationServer -Continue
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $destServer -NoSystemDb

            if ($DestinationDatabase.count -gt 0) {
                $dbs = $dbs | Where-Object { $DestinationDatabase -contains $_.Name }
            }

            if ($Exclude.count -gt 0) {
                $dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
            }

            if ($dbs.count -eq 0) {
                Stop-Function -Message "No matching databases found. Check the spelling and try again." -Continue
            }

            foreach ($db in $dbs) {
                # skipping the database if the source and destination are the same instance
                if (($sourceServer.Name -eq $destinationServer) -and ($SourceDatabase -eq $db.Name)) {
                    continue
                }
                Write-Message -Message "Processing destination database: $db on $destinationServer." -Level Verbose
                $copyQueryStoreStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.name
                    SourceDatabase    = $SourceDatabase
                    DestinationServer = $destinationServer
                    Name              = $db.name
                    Type              = "QueryStore Configuration"
                    Status            = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($db.IsAccessible -eq $false) {
                    $copyQueryStoreStatus.Status = "Skipped"
                    Stop-Function -Message "The database $db on server $destinationServer is not accessible. Skipping database." -Continue
                }

                Write-Message -Message "Executing Set-DbaQueryStoreConfig." -Level Verbose
                # Set the Query Store configuration through the Set-DbaQueryStoreConfig function
                try {
                    $null = Set-DbaQueryStoreConfig -SqlInstance $destinationServer -SqlCredential $DestinationSqlCredential `
                        -Database $db.name `
                        -State $SourceQSConfig.ActualState `
                        -FlushInterval $SourceQSConfig.FlushInterval `
                        -CollectionInterval $SourceQSConfig.CollectionInterval `
                        -MaxSize $SourceQSConfig.MaxSize `
                        -CaptureMode $SourceQSConfig.CaptureMode `
                        -CleanupMode $SourceQSConfig.CleanupMode `
                        -StaleQueryThreshold $SourceQSConfig.StaleQueryThreshold
                    $copyQueryStoreStatus.Status = "Successful"
                }
                catch {
                    $copyQueryStoreStatus.Status = "Failed"
                    Stop-Function -Message "Issue setting Query Store on $db." -Target $db -InnerErrorRecord $_ -Continue
                }
                $copyQueryStoreStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }
    }
}
