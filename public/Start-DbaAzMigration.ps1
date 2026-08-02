function Start-DbaAzMigration {
    <#
    .SYNOPSIS
        Migrates SQL Server databases to an existing Azure SQL Database logical server using BACPAC files.

    .DESCRIPTION
        Exports selected accessible user databases from one SQL Server instance as BACPAC files and imports them into unique staging databases on an existing Azure SQL Database logical server. Each completed staging import is promoted to the source database name after a final collision check.

        This command migrates databases only. It does not provision Azure resources or migrate server-level objects such as logins, credentials, SQL Agent jobs, linked servers, or server roles. Azure SQL Managed Instance migrations should use Copy-DbaDatabase instead.

        Microsoft DacFx is supplied through dbatools.library, so no additional module or SqlPackage installation is required. Generated BACPAC files contain data and are removed after each migration by default.

    .PARAMETER Source
        The source SQL Server instance or reusable connected server object.

    .PARAMETER Destination
        The existing Azure SQL Database logical server or reusable connected server object. The connecting principal must be able to create and, when Force is used, remove databases.

    .PARAMETER SourceSqlCredential
        Credential used to connect to the source SQL Server instance.

    .PARAMETER DestinationSqlCredential
        Credential used to connect to the destination Azure SQL logical server.

    .PARAMETER Database
        The source databases to migrate. When omitted, all accessible user databases are selected.

    .PARAMETER ExcludeDatabase
        Source databases to exclude after applying the Database filter.

    .PARAMETER Path
        Directory used for generated BACPAC files. Defaults to the configured dbatools temporary path.

    .PARAMETER ExportDacOption
        A Microsoft.SqlServer.Dac.DacExportOptions object passed to BACPAC export.

    .PARAMETER ImportDacOption
        A Microsoft.SqlServer.Dac.DacImportOptions object passed to BACPAC import. Use this option to configure the Azure edition, service objective, maximum size, and DacFx import settings.

    .PARAMETER Force
        Replaces a destination database when a database with the same name already exists. The existing database remains in place until the replacement has been fully imported into a staging database.

    .PARAMETER KeepBacpac
        Keeps generated BACPAC files after migration. BACPAC files contain schema and table data and must be secured appropriately.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Azure, Database, Bacpac
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaAzMigration

    .OUTPUTS
        PSCustomObject

        Returns one dbatools.MigrationObject per selected database.

        Default display properties (via Select-DefaultView):
        - DateTime (DbaDateTime): The date and time when processing of the database began
        - SourceServer (String): The connected source SQL Server name
        - DestinationServer (String): The connected Azure SQL logical server name
        - Name (String): The source database name
        - Type (String): The migrated object type, always Database
        - Status (String): The migration result, such as Successful, Failed, or Skipped
        - Notes (String): Failure, cleanup, or skip details when applicable

        Additional properties available:
        - DestinationDatabase (String): The final Azure SQL database name
        - BacpacPath (String): The generated BACPAC path; the file is removed by default unless KeepBacpac is specified
        - Elapsed (prettytimespan): The elapsed processing time for the database

    .EXAMPLE
        PS C:\> Start-DbaAzMigration -Source sql01 -Destination dbatools.database.windows.net -Database AppDb

        Migrates AppDb to the existing Azure SQL logical server and removes the temporary BACPAC after import.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Bacpac -Action Publish
        PS C:\> $options.DatabaseSpecification.Edition = "Standard"
        PS C:\> $options.DatabaseSpecification.ServiceObjective = "S0"
        PS C:\> Start-DbaAzMigration -Source sql01 -Destination dbatools.database.windows.net -ImportDacOption $options -Force -Confirm:$false

        Migrates all accessible user databases and replaces databases that already exist, using the selected Azure service objective.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$Path = (Get-DbatoolsConfigValue -FullName "Path.DbatoolsTemp"),
        [object]$ExportDacOption,
        [object]$ImportDacOption,
        [switch]$Force,
        [switch]$KeepBacpac,
        [switch]$EnableException
    )

    begin {
        $resolveDatabaseName = {
            param($DatabaseInput)

            if ($null -ne $DatabaseInput -and $DatabaseInput.PSObject.Properties["Name"] -and $DatabaseInput.Name) {
                [string]$DatabaseInput.Name
            } else {
                [string]$DatabaseInput
            }
        }

        if ((Test-Bound -ParameterName ExportDacOption) -and $ExportDacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
            $exportOptionType = if ($null -eq $ExportDacOption) { "null" } else { $ExportDacOption.GetType() }
            Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected for ExportDacOption - got $exportOptionType." -EnableException $EnableException
            return
        }

        if ((Test-Bound -ParameterName ImportDacOption) -and $ImportDacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
            $importOptionType = if ($null -eq $ImportDacOption) { "null" } else { $ImportDacOption.GetType() }
            Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected for ImportDacOption - got $importOptionType." -EnableException $EnableException
            return
        }

        $databaseWasBound = Test-Bound -ParameterName Database
        $requestedDatabaseNames = @()
        if ($databaseWasBound) {
            $requestedDatabaseNames = @($Database | ForEach-Object { & $resolveDatabaseName $PSItem })
            $blankRequestedDatabaseNames = @($requestedDatabaseNames | Where-Object { [string]::IsNullOrWhiteSpace($PSItem) })
            if ($requestedDatabaseNames.Count -eq 0 -or $blankRequestedDatabaseNames.Count -gt 0) {
                Stop-Function -Message "Database must contain at least one non-blank database name when explicitly supplied." -EnableException $EnableException
                return
            }
        }

        try {
            if (Test-Path -LiteralPath $Path) {
                if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                    throw "Path ($Path) must be a directory."
                }
            } else {
                $splatNewPath = @{
                    Path        = $Path
                    ItemType    = "Directory"
                    Force       = $true
                    ErrorAction = "Stop"
                }
                $null = New-Item @splatNewPath
            }
        } catch {
            $splatStopPath = @{
                Message         = "Path ($Path) must be a directory that can be created and written."
                ErrorRecord     = $PSItem
                Target          = $Path
                EnableException = $EnableException
            }
            Stop-Function @splatStopPath
            return
        }

        try {
            if ($SourceSqlCredential) {
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            } else {
                $sourceServer = Connect-DbaInstance -SqlInstance $Source
            }
        } catch {
            $splatStopSourceConnection = @{
                Message         = "Failure connecting to source $Source"
                Category        = "ConnectionError"
                ErrorRecord     = $PSItem
                Target          = $Source
                EnableException = $EnableException
            }
            Stop-Function @splatStopSourceConnection
            return
        }

        try {
            $splatDestination = @{
                SqlInstance = $Destination
                Database    = "master"
            }
            if ($DestinationSqlCredential) {
                $splatDestination.SqlCredential = $DestinationSqlCredential
            }
            $destinationServer = Connect-DbaInstance @splatDestination
        } catch {
            $splatStopDestinationConnection = @{
                Message         = "Failure connecting to destination $Destination"
                Category        = "ConnectionError"
                ErrorRecord     = $PSItem
                Target          = $Destination
                EnableException = $EnableException
            }
            Stop-Function @splatStopDestinationConnection
            return
        }

        if ($destinationServer.DatabaseEngineType -ne "SqlAzureDatabase" -or $destinationServer.DatabaseEngineEdition -ne "SqlDatabase") {
            $splatStopDestinationType = @{
                Message         = "$Destination is not an Azure SQL Database logical server. Use Copy-DbaDatabase for Azure SQL Managed Instance migrations."
                Target          = $Destination
                EnableException = $EnableException
            }
            Stop-Function @splatStopDestinationType
            return
        }

        if ($Destination.IsConnectionString) {
            $destinationConnectionString = [string]$Destination.InputObject
        } else {
            $destinationConnectionString = $destinationServer.ConnectionContext.ConnectionString
        }

        $connectionBuilder = New-Object System.Data.Common.DbConnectionStringBuilder
        $connectionBuilder.ConnectionString = $destinationConnectionString
        $null = $connectionBuilder.Remove("Initial Catalog")
        $null = $connectionBuilder.Remove("Database")
        $connectionBuilder["Database"] = "master"
        if ($DestinationSqlCredential) {
            $null = $connectionBuilder.Remove("Integrated Security")
            $null = $connectionBuilder.Remove("Trusted_Connection")
            $connectionBuilder["User ID"] = $DestinationSqlCredential.UserName
            $connectionBuilder["Password"] = $DestinationSqlCredential.GetNetworkCredential().Password
        }
        $destinationPublishConnectionString = $connectionBuilder.ConnectionString

        $sensitiveValues = @()
        if ($SourceSqlCredential) {
            $sensitiveValues += $SourceSqlCredential.GetNetworkCredential().Password
        }
        if ($DestinationSqlCredential) {
            $sensitiveValues += $DestinationSqlCredential.GetNetworkCredential().Password
        }
        foreach ($connectionStringToInspect in @($sourceServer.ConnectionContext.ConnectionString, $destinationPublishConnectionString)) {
            try {
                $secretBuilder = New-Object System.Data.Common.DbConnectionStringBuilder
                $secretBuilder.ConnectionString = $connectionStringToInspect
                foreach ($passwordKey in @("Password", "Pwd")) {
                    if ($secretBuilder.ContainsKey($passwordKey) -and $secretBuilder[$passwordKey]) {
                        $sensitiveValues += [string]$secretBuilder[$passwordKey]
                    }
                }
            } catch {
                Write-Message -Level Debug -Message "Could not inspect a connection string for values that require redaction."
            }
        }
        $sensitiveValues = @($sensitiveValues | Where-Object { $PSItem } | Select-Object -Unique)

        $getDatabaseIdentity = {
            param($DatabaseObject)

            if (-not $DatabaseObject) {
                return $null
            }

            $splatGetDatabaseIdentity = @{
                SqlInstance     = $destinationServer
                Database        = "master"
                Query           = "SELECT CONVERT(nvarchar(36), service_broker_guid) + '|' + CONVERT(nvarchar(11), database_id) FROM sys.databases WHERE name = @DatabaseName"
                SqlParameter    = @{ DatabaseName = $DatabaseObject.Name }
                As              = "SingleValue"
                EnableException = $true
            }
            $databaseIdentity = Invoke-DbaQuery @splatGetDatabaseIdentity
            if (-not $databaseIdentity) {
                throw "The identity of Azure SQL database $($DatabaseObject.Name) could not be read."
            }

            [string]$databaseIdentity
        }

        try {
            $splatGetAccessibleDatabase = @{
                SqlInstance     = $sourceServer
                ExcludeSystem   = $true
                OnlyAccessible  = $true
                EnableException = $true
            }
            $accessibleDatabases = @(Get-DbaDatabase @splatGetAccessibleDatabase)
        } catch {
            $splatStopDatabaseEnumeration = @{
                Message         = "Failure enumerating accessible user databases on source $Source"
                ErrorRecord     = $PSItem
                Target          = $Source
                EnableException = $EnableException
            }
            Stop-Function @splatStopDatabaseEnumeration
            return
        }

        $excludedDatabaseNames = @()
        if ($ExcludeDatabase) {
            $excludedDatabaseNames = @($ExcludeDatabase | ForEach-Object { & $resolveDatabaseName $PSItem })
        }

        if ($databaseWasBound) {
            $accessibleDatabaseNames = @($accessibleDatabases.Name)
            $missingDatabaseNames = @($requestedDatabaseNames | Where-Object { $PSItem -notin $accessibleDatabaseNames })
            if ($missingDatabaseNames.Count -gt 0) {
                $splatStopMissingDatabase = @{
                    Message         = "The following requested databases were not found or are not accessible on ${Source}: $($missingDatabaseNames -join ", ")."
                    Target          = $Source
                    EnableException = $EnableException
                }
                Stop-Function @splatStopMissingDatabase
                return
            }
            $selectedDatabases = @($requestedDatabaseNames | Select-Object -Unique | ForEach-Object {
                    $requestedName = $PSItem
                    $accessibleDatabases | Where-Object Name -EQ $requestedName | Select-Object -First 1
                })
        } else {
            $selectedDatabases = @($accessibleDatabases)
        }

        if ($excludedDatabaseNames.Count -gt 0) {
            $selectedDatabases = @($selectedDatabases | Where-Object { $PSItem.Name -notin $excludedDatabaseNames })
        }

        if ($selectedDatabases.Count -eq 0) {
            $splatStopEmptySelection = @{
                Message         = "No accessible user databases remain on $Source after applying the requested filters."
                Target          = $Source
                EnableException = $EnableException
            }
            Stop-Function @splatStopEmptySelection
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($sourceDatabase in $selectedDatabases) {
            $databaseName = $sourceDatabase.Name
            $destinationDatabase = $null
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $migrationStatus = [pscustomobject][ordered]@{
                SourceServer        = $sourceServer.Name
                DestinationServer   = $destinationServer.Name
                Name                = $databaseName
                DestinationDatabase = $databaseName
                Type                = "Database"
                Status              = $null
                Notes               = $null
                DateTime            = [DbaDateTime](Get-Date)
                BacpacPath          = $null
                Elapsed             = $null
            }
            $migrationViewProperties = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            $splatGetDestinationDatabase = @{
                SqlInstance     = $destinationServer
                Database        = $databaseName
                EnableException = $true
            }

            try {
                $destinationServer.Databases.Refresh()
                $destinationDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                $destinationDatabaseIdentity = & $getDatabaseIdentity $destinationDatabase
            } catch {
                $stopwatch.Stop()
                $migrationStatus.Status = "Failed"
                $migrationStatus.Notes = "Destination validation failed: $($PSItem.Exception.Message)"
                foreach ($sensitiveValue in $sensitiveValues) {
                    $migrationStatus.Notes = $migrationStatus.Notes.Replace($sensitiveValue, "********")
                }
                $migrationStatus.Elapsed = [prettytimespan]$stopwatch.Elapsed
                $migrationStatus | Select-DefaultView -Property $migrationViewProperties -TypeName "MigrationObject"
                $splatStopDestinationValidation = @{
                    Message         = "Destination validation failed for database $databaseName"
                    ErrorRecord     = $PSItem
                    Target          = $databaseName
                    EnableException = $EnableException
                    Continue        = $true
                }
                Stop-Function @splatStopDestinationValidation
            }

            if ($destinationDatabase -and -not $Force) {
                $stopwatch.Stop()
                $migrationStatus.Status = "Skipped"
                $migrationStatus.Notes = "Already exists on destination"
                $migrationStatus.Elapsed = [prettytimespan]$stopwatch.Elapsed
                $migrationStatus | Select-DefaultView -Property $migrationViewProperties -TypeName "MigrationObject"
                continue
            }

            if ($destinationDatabase) {
                if (-not $PSCmdlet.ShouldProcess("$databaseName on $($destinationServer.Name)", "Drop the existing Azure SQL database and migrate its replacement")) {
                    continue
                }
            } elseif (-not $PSCmdlet.ShouldProcess("$databaseName on $($destinationServer.Name)", "Migrate database to Azure SQL Database")) {
                continue
            }

            Write-Message -Level Verbose -Message "Destination state captured for $databaseName. Starting BACPAC export."

            $safeDatabaseName = $databaseName.Split([IO.Path]::GetInvalidFileNameChars()) -join "$"
            $bacpacPath = Join-DbaPath -Path $Path -Child "$safeDatabaseName-$([guid]::NewGuid().ToString("N")).bacpac"
            $migrationStatus.BacpacPath = $bacpacPath
            $failureRecord = $null
            $failurePhase = $null
            $cleanupNotes = @()
            $destinationExistedBeforeExport = [bool]$destinationDatabase
            $safeStagingSourceName = $databaseName -replace "[^a-zA-Z0-9_]", "_"
            if ($safeStagingSourceName.Length -gt 60) {
                $safeStagingSourceName = $safeStagingSourceName.Substring(0, 60)
            }
            $stagingDatabaseName = "dbatools_azmigration_${safeStagingSourceName}_$([guid]::NewGuid().ToString("N"))"
            $backupDatabaseName = "dbatools_azmigration_backup_${safeStagingSourceName}_$([guid]::NewGuid().ToString("N"))"
            $stagingDatabaseMayNeedCleanup = $false
            $backupDatabaseMayNeedRecovery = $false
            $stagingDatabaseIdentity = $null

            try {
                $failurePhase = "BACPAC export"
                $splatExport = @{
                    SqlInstance     = $sourceServer
                    Database        = $databaseName
                    FilePath        = $bacpacPath
                    Type            = "Bacpac"
                    EnableException = $true
                }
                if ($ExportDacOption) {
                    $splatExport.DacOption = $ExportDacOption
                }
                $exportResult = @(Export-DbaDacPackage @splatExport)
                if ($exportResult.Count -ne 1 -or -not $exportResult[0].Path -or -not (Test-Path -LiteralPath $exportResult[0].Path)) {
                    throw "BACPAC export did not produce exactly one readable package."
                }
                $bacpacPath = $exportResult[0].Path
                $migrationStatus.BacpacPath = $bacpacPath

                $failurePhase = "Staging database validation"
                $destinationServer.Databases.Refresh()
                $splatGetDestinationDatabase.Database = $stagingDatabaseName
                $unexpectedStagingDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                if ($unexpectedStagingDatabase) {
                    throw "The unique staging database name already exists."
                }

                $failurePhase = "BACPAC import"
                $stagingDatabaseMayNeedCleanup = $true
                $splatPublish = @{
                    ConnectionString = $destinationPublishConnectionString
                    Database         = $stagingDatabaseName
                    Path             = $bacpacPath
                    Type             = "Bacpac"
                    EnableException  = $true
                    Confirm          = $false
                }
                if ($ImportDacOption) {
                    $splatPublish.DacOption = $ImportDacOption
                }
                $publishResult = @(Publish-DbaDacPackage @splatPublish)
                if ($publishResult.Count -ne 1 -or $publishResult[0].Database -ne $stagingDatabaseName) {
                    throw "BACPAC import did not return a result for staging database $stagingDatabaseName."
                }

                $failurePhase = "Destination promotion"
                $destinationServer.Databases.Refresh()
                $splatGetDestinationDatabase.Database = $stagingDatabaseName
                $stagingDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                if (-not $stagingDatabase) {
                    throw "BACPAC import did not create staging database $stagingDatabaseName."
                }
                $stagingDatabaseIdentity = & $getDatabaseIdentity $stagingDatabase

                $splatGetDestinationDatabase.Database = $databaseName
                $currentDestinationDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                if (-not $destinationExistedBeforeExport -and $currentDestinationDatabase) {
                    throw "A destination database named $databaseName appeared while the BACPAC was being imported. It was not created or removed by this migration."
                }

                if ($destinationExistedBeforeExport) {
                    if (-not $currentDestinationDatabase) {
                        throw "The original destination database $databaseName disappeared while the BACPAC was being imported. Promotion stopped without claiming the final name."
                    }

                    $currentDestinationDatabaseIdentity = & $getDatabaseIdentity $currentDestinationDatabase
                    if ($currentDestinationDatabaseIdentity -ne $destinationDatabaseIdentity) {
                        throw "The destination database $databaseName was replaced while the BACPAC was being imported. The replacement was not modified or removed."
                    }

                    try {
                        $backupDatabaseMayNeedRecovery = $true
                        $currentDestinationDatabase.Rename($backupDatabaseName)
                        $destinationServer.Databases.Refresh()
                        $splatGetDestinationDatabase.Database = $backupDatabaseName
                        $backupDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if (-not $backupDatabase) {
                            throw "The original destination database could not be verified at recovery name $backupDatabaseName."
                        }
                        $backupDatabaseIdentity = & $getDatabaseIdentity $backupDatabase
                        if ($backupDatabaseIdentity -ne $destinationDatabaseIdentity) {
                            $splatGetDestinationDatabase.Database = $databaseName
                            $concurrentFinalDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                            if (-not $concurrentFinalDatabase) {
                                $backupDatabase.Rename($databaseName)
                                $destinationServer.Databases.Refresh()
                                $restoredConcurrentDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                                if (-not $restoredConcurrentDatabase -or (& $getDatabaseIdentity $restoredConcurrentDatabase) -ne $backupDatabaseIdentity) {
                                    throw "A replacement database was renamed during forced promotion and could not be verified after restoration to $databaseName."
                                }
                                $backupDatabaseMayNeedRecovery = $false
                                throw "The destination database $databaseName was replaced during forced promotion. The replacement was restored to its final name and the staging database was not promoted."
                            }
                            throw "The destination database $databaseName was replaced during forced promotion, and the final name was claimed before the replacement could be restored. Recovery databases were preserved."
                        }

                        $splatGetDestinationDatabase.Database = $databaseName
                        $unexpectedFinalDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if ($unexpectedFinalDatabase) {
                            throw "The final database name $databaseName was claimed during forced promotion."
                        }

                        $stagingDatabase.Rename($databaseName)
                        $destinationServer.Databases.Refresh()
                        $promotedDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if (-not $promotedDatabase -or (& $getDatabaseIdentity $promotedDatabase) -ne $stagingDatabaseIdentity) {
                            throw "The staging database could not be verified after promotion to $databaseName."
                        }
                        $stagingDatabaseMayNeedCleanup = $false

                        $splatGetDestinationDatabase.Database = $backupDatabaseName
                        $backupDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if ($backupDatabase) {
                            # Azure SQL only supports name-based deletion. Recheck the GUID-owned name immediately before removal.
                            if ((& $getDatabaseIdentity $backupDatabase) -ne $destinationDatabaseIdentity) {
                                throw "The recovery database $backupDatabaseName no longer identifies the original destination database."
                            }
                            $splatRemoveBackup = @{
                                InputObject     = $backupDatabase
                                Confirm         = $false
                                EnableException = $true
                            }
                            $null = Remove-DbaDatabase @splatRemoveBackup
                        }
                        $destinationServer.Databases.Refresh()
                        $remainingBackupDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if ($remainingBackupDatabase) {
                            throw "The original destination database could not be removed from recovery name $backupDatabaseName."
                        }
                        $backupDatabaseMayNeedRecovery = $false
                    } catch {
                        $promotionError = $PSItem
                        if ($backupDatabaseMayNeedRecovery) {
                            try {
                                $destinationServer.Databases.Refresh()
                                $splatGetDestinationDatabase.Database = $databaseName
                                $recoveryFinalDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                                $splatGetDestinationDatabase.Database = $backupDatabaseName
                                $recoveryBackupDatabase = Get-DbaDatabase @splatGetDestinationDatabase

                                $recoveryFinalIdentity = & $getDatabaseIdentity $recoveryFinalDatabase
                                $recoveryBackupIdentity = & $getDatabaseIdentity $recoveryBackupDatabase
                                if (-not $recoveryFinalDatabase -and $recoveryBackupIdentity -eq $destinationDatabaseIdentity) {
                                    $recoveryBackupDatabase.Rename($databaseName)
                                    $destinationServer.Databases.Refresh()
                                    $splatGetDestinationDatabase.Database = $databaseName
                                    $restoredDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                                    if (-not $restoredDatabase -or (& $getDatabaseIdentity $restoredDatabase) -ne $destinationDatabaseIdentity) {
                                        throw "The original destination database could not be verified after rollback."
                                    }
                                    $backupDatabaseMayNeedRecovery = $false
                                    $cleanupNotes += "The original destination database was restored after promotion failed."
                                } elseif ($recoveryFinalIdentity -eq $stagingDatabaseIdentity) {
                                    $stagingDatabaseMayNeedCleanup = $false
                                    $cleanupNotes += "Promotion reached $databaseName, but the original database is retained at $backupDatabaseName because promotion cleanup failed."
                                } elseif ($recoveryFinalIdentity -eq $destinationDatabaseIdentity -and -not $recoveryBackupDatabase) {
                                    $backupDatabaseMayNeedRecovery = $false
                                    $cleanupNotes += "The original destination database was already restored after promotion failed."
                                } else {
                                    $stagingDatabaseMayNeedCleanup = $false
                                    $cleanupNotes += "Automatic rollback was not safe. Recovery databases were preserved as $stagingDatabaseName and $backupDatabaseName where present."
                                }
                            } catch {
                                $stagingDatabaseMayNeedCleanup = $false
                                $cleanupNotes += "Promotion rollback failed: $($PSItem.Exception.Message) Recovery databases were preserved as $stagingDatabaseName and $backupDatabaseName where present."
                            }
                        }
                        throw $promotionError
                    }
                } else {
                    $stagingDatabase.Rename($databaseName)
                    $destinationServer.Databases.Refresh()
                    $promotedDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                    if (-not $promotedDatabase -or (& $getDatabaseIdentity $promotedDatabase) -ne $stagingDatabaseIdentity) {
                        throw "The staging database could not be verified after promotion to $databaseName."
                    }
                    $stagingDatabaseMayNeedCleanup = $false
                }
                $migrationStatus.Status = "Successful"
            } catch {
                $failureRecord = $PSItem
                $migrationStatus.Status = "Failed"

                if ($stagingDatabaseMayNeedCleanup) {
                    try {
                        $destinationServer.Databases.Refresh()
                        $splatGetDestinationDatabase.Database = $stagingDatabaseName
                        $partialStagingDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                        if ($partialStagingDatabase) {
                            $partialStagingDatabaseIdentity = & $getDatabaseIdentity $partialStagingDatabase
                            if (-not $stagingDatabaseIdentity) {
                                $stagingDatabaseMayNeedCleanup = $false
                                $cleanupNotes += "The partial staging database $stagingDatabaseName was preserved because its ownership could not be verified after import failure."
                            } elseif ($partialStagingDatabaseIdentity -ne $stagingDatabaseIdentity) {
                                $stagingDatabaseMayNeedCleanup = $false
                                $cleanupNotes += "A database replaced staging database $stagingDatabaseName before cleanup. The replacement was preserved."
                            } else {
                                # Azure SQL only supports name-based deletion. Recheck the GUID-owned name immediately before removal.
                                $splatRemoveStaging = @{
                                    InputObject     = $partialStagingDatabase
                                    Confirm         = $false
                                    EnableException = $true
                                }
                                $null = Remove-DbaDatabase @splatRemoveStaging
                                $destinationServer.Databases.Refresh()
                                $remainingStagingDatabase = Get-DbaDatabase @splatGetDestinationDatabase
                                if ($remainingStagingDatabase) {
                                    throw "The partially imported staging database could not be dropped."
                                }
                                $stagingDatabaseMayNeedCleanup = $false
                            }
                        }
                    } catch {
                        $cleanupNotes += "Partial staging database cleanup failed: $($PSItem.Exception.Message)"
                    }
                }
            } finally {
                if (-not $KeepBacpac -and $bacpacPath -and (Test-Path -LiteralPath $bacpacPath)) {
                    try {
                        $splatRemoveBacpac = @{
                            LiteralPath = $bacpacPath
                            Force       = $true
                            ErrorAction = "Stop"
                        }
                        Remove-Item @splatRemoveBacpac
                    } catch {
                        $cleanupNotes += "BACPAC cleanup failed: $($PSItem.Exception.Message)"
                        if (-not $failureRecord) {
                            $failureRecord = $PSItem
                            $failurePhase = "BACPAC cleanup"
                            $migrationStatus.Status = "Failed"
                        }
                    }
                }
                $stopwatch.Stop()
                $migrationStatus.Elapsed = [prettytimespan]$stopwatch.Elapsed
            }

            $failureMessage = $null
            if ($failureRecord) {
                $failureMessage = "$failurePhase failed for database ${databaseName}: $($failureRecord.Exception.Message)"
                if ($failureRecord.Exception.Message -match "TSQL CRUD has been disallowed via policy") {
                    $failureMessage = "$failureMessage The Azure subscription blocks database creation and deletion through T-SQL. DacFx BACPAC import requires those operations; use a destination subscription where block-tsql-crud is not registered or ask the subscription administrator to remove that policy."
                }
                $migrationStatus.Notes = $failureMessage
            }
            if ($cleanupNotes.Count -gt 0) {
                if ($migrationStatus.Notes) {
                    $migrationStatus.Notes = "$($migrationStatus.Notes) $($cleanupNotes -join " ")"
                } else {
                    $migrationStatus.Notes = $cleanupNotes -join " "
                }
            }

            if ($failureRecord -and $migrationStatus.Notes) {
                foreach ($sensitiveValue in $sensitiveValues) {
                    $migrationStatus.Notes = $migrationStatus.Notes.Replace($sensitiveValue, "********")
                }
                $failureMessage = $migrationStatus.Notes
            }

            $migrationStatus | Select-DefaultView -Property $migrationViewProperties -TypeName "MigrationObject"

            if ($failureRecord) {
                $safeException = New-Object System.Exception -ArgumentList $failureMessage
                $safeErrorRecord = New-Object System.Management.Automation.ErrorRecord -ArgumentList $safeException, $failureRecord.FullyQualifiedErrorId, $failureRecord.CategoryInfo.Category, $databaseName
                $splatStopMigration = @{
                    Message         = $failureMessage
                    ErrorRecord     = $safeErrorRecord
                    Target          = $databaseName
                    EnableException = $EnableException
                    Continue        = $true
                }
                Stop-Function @splatStopMigration
            }
        }
    }
}
