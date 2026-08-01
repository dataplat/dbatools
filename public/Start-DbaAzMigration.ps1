function Start-DbaAzMigration {
    <#
    .SYNOPSIS
        Migrates SQL Server databases to an existing Azure SQL Database logical server using BACPAC files.

    .DESCRIPTION
        Exports selected accessible user databases from one SQL Server instance as BACPAC files and imports them into an existing Azure SQL Database logical server with the same database names.

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
        Drops and recreates a destination database when a database with the same name already exists.

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

        Returns one MigrationObject per selected database with SourceServer, DestinationServer, Name, DestinationDatabase, Type, Status, Notes, DateTime, BacpacPath, and Elapsed properties.

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
        if ($ExportDacOption -and $ExportDacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
            Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected for ExportDacOption - got $($ExportDacOption.GetType())." -EnableException $EnableException
            return
        }

        if ($ImportDacOption -and $ImportDacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
            Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected for ImportDacOption - got $($ImportDacOption.GetType())." -EnableException $EnableException
            return
        }

        $null = Test-ExportDirectory -Path $Path
        if (Test-FunctionInterrupt) { return }

        try {
            $sourceSplat = @{
                SqlInstance = $Source
            }
            if ($SourceSqlCredential) {
                $sourceSplat.SqlCredential = $SourceSqlCredential
            }
            $sourceServer = Connect-DbaInstance @sourceSplat
        } catch {
            Stop-Function -Message "Failure connecting to source $Source" -Category ConnectionError -ErrorRecord $PSItem -Target $Source -EnableException $EnableException
            return
        }

        try {
            $destinationSplat = @{
                SqlInstance = $Destination
                Database    = "master"
            }
            if ($DestinationSqlCredential) {
                $destinationSplat.SqlCredential = $DestinationSqlCredential
            }
            $destinationServer = Connect-DbaInstance @destinationSplat
        } catch {
            Stop-Function -Message "Failure connecting to destination $Destination" -Category ConnectionError -ErrorRecord $PSItem -Target $Destination -EnableException $EnableException
            return
        }

        if ($destinationServer.DatabaseEngineType -ne "SqlAzureDatabase" -or $destinationServer.DatabaseEngineEdition -ne "SqlDatabase") {
            Stop-Function -Message "$Destination is not an Azure SQL Database logical server. Use Copy-DbaDatabase for Azure SQL Managed Instance migrations." -Target $Destination -EnableException $EnableException
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

        try {
            $accessibleDatabases = @(Get-DbaDatabase -SqlInstance $sourceServer -ExcludeSystem -OnlyAccessible -EnableException)
        } catch {
            Stop-Function -Message "Failure enumerating accessible user databases on source $Source" -ErrorRecord $PSItem -Target $Source -EnableException $EnableException
            return
        }

        $requestedDatabaseNames = @()
        if ($Database) {
            $requestedDatabaseNames = @($Database | ForEach-Object {
                    if ($PSItem.PSObject.Properties["Name"] -and $PSItem.Name) {
                        [string]$PSItem.Name
                    } else {
                        [string]$PSItem
                    }
                })
        }
        $excludedDatabaseNames = @()
        if ($ExcludeDatabase) {
            $excludedDatabaseNames = @($ExcludeDatabase | ForEach-Object {
                    if ($PSItem.PSObject.Properties["Name"] -and $PSItem.Name) {
                        [string]$PSItem.Name
                    } else {
                        [string]$PSItem
                    }
                })
        }

        if ($requestedDatabaseNames.Count -gt 0) {
            $accessibleDatabaseNames = @($accessibleDatabases.Name)
            $missingDatabaseNames = @($requestedDatabaseNames | Where-Object { $PSItem -notin $accessibleDatabaseNames })
            if ($missingDatabaseNames.Count -gt 0) {
                Stop-Function -Message "The following requested databases were not found or are not accessible on $Source`: $($missingDatabaseNames -join ', ')." -Target $Source -EnableException $EnableException
                return
            }
            $selectedDatabases = @($accessibleDatabases | Where-Object { $PSItem.Name -in $requestedDatabaseNames })
        } else {
            $selectedDatabases = @($accessibleDatabases)
        }

        if ($excludedDatabaseNames.Count -gt 0) {
            $selectedDatabases = @($selectedDatabases | Where-Object { $PSItem.Name -notin $excludedDatabaseNames })
        }

        if ($selectedDatabases.Count -eq 0) {
            Stop-Function -Message "No accessible user databases remain on $Source after applying the requested filters." -Target $Source -EnableException $EnableException
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

            try {
                $destinationServer.Databases.Refresh()
                $destinationDatabase = Get-DbaDatabase -SqlInstance $destinationServer -Database $databaseName -EnableException
            } catch {
                $stopwatch.Stop()
                $migrationStatus.Status = "Failed"
                $migrationStatus.Notes = "Destination validation failed: $($PSItem.Exception.Message)"
                $migrationStatus.Elapsed = [prettytimespan]$stopwatch.Elapsed
                $migrationStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                Stop-Function -Message "Destination validation failed for database $databaseName" -ErrorRecord $PSItem -Target $databaseName -EnableException $EnableException -Continue
            }

            if ($destinationDatabase -and -not $Force) {
                $stopwatch.Stop()
                $migrationStatus.Status = "Skipped"
                $migrationStatus.Notes = "Already exists on destination"
                $migrationStatus.Elapsed = [prettytimespan]$stopwatch.Elapsed
                $migrationStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                continue
            }

            if ($destinationDatabase) {
                if (-not $PSCmdlet.ShouldProcess("$databaseName on $($destinationServer.Name)", "Drop the existing Azure SQL database and migrate its replacement")) {
                    continue
                }
            } elseif (-not $PSCmdlet.ShouldProcess("$databaseName on $($destinationServer.Name)", "Migrate database to Azure SQL Database")) {
                continue
            }

            $safeDatabaseName = $databaseName.Split([IO.Path]::GetInvalidFileNameChars()) -join "$"
            $bacpacPath = Join-DbaPath -Path $Path -Child "$safeDatabaseName-$([guid]::NewGuid().ToString('N')).bacpac"
            $migrationStatus.BacpacPath = $bacpacPath
            $failureRecord = $null
            $failurePhase = $null
            $cleanupNotes = @()
            $importStarted = $false
            $targetMayNeedCleanup = -not [bool]$destinationDatabase

            try {
                $failurePhase = "BACPAC export"
                $exportSplat = @{
                    SqlInstance     = $sourceServer
                    Database        = $databaseName
                    FilePath        = $bacpacPath
                    Type            = "Bacpac"
                    EnableException = $true
                }
                if ($ExportDacOption) {
                    $exportSplat.DacOption = $ExportDacOption
                }
                $exportResult = @(Export-DbaDacPackage @exportSplat)
                if ($exportResult.Count -ne 1 -or -not $exportResult[0].Path -or -not (Test-Path -LiteralPath $exportResult[0].Path)) {
                    throw "BACPAC export did not produce exactly one readable package."
                }
                $bacpacPath = $exportResult[0].Path
                $migrationStatus.BacpacPath = $bacpacPath

                if ($destinationDatabase) {
                    $failurePhase = "Forced replacement"
                    $null = Remove-DbaDatabase -InputObject $destinationDatabase -Confirm:$false -EnableException
                    $destinationServer.Databases.Refresh()
                    $remainingDatabase = Get-DbaDatabase -SqlInstance $destinationServer -Database $databaseName -EnableException
                    if ($remainingDatabase) {
                        throw "The existing destination database could not be dropped."
                    }
                    $targetMayNeedCleanup = $true
                }

                $failurePhase = "BACPAC import"
                $importStarted = $true
                $publishSplat = @{
                    ConnectionString = $destinationPublishConnectionString
                    Database         = $databaseName
                    Path             = $bacpacPath
                    Type             = "Bacpac"
                    EnableException  = $true
                    Confirm          = $false
                }
                if ($ImportDacOption) {
                    $publishSplat.DacOption = $ImportDacOption
                }
                $publishResult = @(Publish-DbaDacPackage @publishSplat)
                if ($publishResult.Count -ne 1 -or $publishResult[0].Database -ne $databaseName) {
                    throw "BACPAC import did not return a result for $databaseName."
                }

                $migrationStatus.Status = "Successful"
            } catch {
                $failureRecord = $PSItem
                $migrationStatus.Status = "Failed"

                if ($importStarted -and $targetMayNeedCleanup) {
                    try {
                        $destinationServer.Databases.Refresh()
                        $partialDatabase = Get-DbaDatabase -SqlInstance $destinationServer -Database $databaseName -EnableException
                        if ($partialDatabase) {
                            $null = Remove-DbaDatabase -InputObject $partialDatabase -Confirm:$false -EnableException
                            $destinationServer.Databases.Refresh()
                            $remainingPartialDatabase = Get-DbaDatabase -SqlInstance $destinationServer -Database $databaseName -EnableException
                            if ($remainingPartialDatabase) {
                                throw "The partially imported destination database could not be dropped."
                            }
                        }
                    } catch {
                        $cleanupNotes += "Partial destination cleanup failed: $($PSItem.Exception.Message)"
                    }
                }
            } finally {
                if (-not $KeepBacpac -and $bacpacPath -and (Test-Path -LiteralPath $bacpacPath)) {
                    try {
                        Remove-Item -LiteralPath $bacpacPath -Force -ErrorAction Stop
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
                $failureMessage = "$failurePhase failed for database $databaseName`: $($failureRecord.Exception.Message)"
                if ($failureRecord.Exception.Message -match "TSQL CRUD has been disallowed via policy") {
                    $failureMessage = "$failureMessage The Azure subscription blocks database creation and deletion through T-SQL. DacFx BACPAC import requires those operations; use a destination subscription where block-tsql-crud is not registered or ask the subscription administrator to remove that policy."
                }
                $migrationStatus.Notes = $failureMessage
            }
            if ($cleanupNotes.Count -gt 0) {
                if ($migrationStatus.Notes) {
                    $migrationStatus.Notes = "$($migrationStatus.Notes) $($cleanupNotes -join ' ')"
                } else {
                    $migrationStatus.Notes = $cleanupNotes -join " "
                }
            }

            $migrationStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

            if ($failureRecord) {
                Stop-Function -Message $failureMessage -Target $databaseName -EnableException $EnableException -Continue
            }
        }
    }
}