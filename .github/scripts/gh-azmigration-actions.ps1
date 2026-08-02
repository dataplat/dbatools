#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "", Justification = "Uses the public disposable SQL container credential from the integration workflow.")]
param()

Describe "Start-DbaAzMigration Azure SQL boundary" -Tag "IntegrationTests" {
    It "covers selection, failure semantics, race safety, replacement, and cleanup against Azure SQL Database" {
        if (-not ($env:TENANTID -and $env:CLIENTID -and $env:CLIENTSECRET)) {
            throw "Start-DbaAzMigration Azure integration requires TENANTID, CLIENTID, and CLIENTSECRET."
        }

        $sourcePassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $sourceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sqladmin", $sourcePassword
        $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 8)
        $databaseName = "dbatoolsci_azmigration_$suffix"
        $excludedDatabaseName = "dbatoolsci_azexclude_$suffix"
        $friendlyFailureDatabaseName = "dbatoolsci_azfriendlyfail_$suffix"
        $friendlySuccessDatabaseName = "dbatoolsci_azfriendlyok_$suffix"
        $exceptionFailureDatabaseName = "dbatoolsci_azexceptionfail_$suffix"
        $exceptionNotRunDatabaseName = "dbatoolsci_azexceptionnotrun_$suffix"
        $importFailureDatabaseName = "dbatoolsci_azimportfail_$suffix"
        $publishFailureDatabaseName = "dbatoolsci_azpublishfail_$suffix"
        $appearanceRaceDatabaseName = "dbatoolsci_azappear_$suffix"
        $appearanceRacerDatabaseName = "dbatoolsci_azappear_racer_$suffix"
        $raceDatabaseName = "dbatoolsci_azrace_$suffix"
        $replacementRacerDatabaseName = "dbatoolsci_azrace_racer_$suffix"
        $sourceDatabaseNames = @(
            $databaseName
            $excludedDatabaseName
            $friendlyFailureDatabaseName
            $friendlySuccessDatabaseName
            $exceptionFailureDatabaseName
            $exceptionNotRunDatabaseName
            $importFailureDatabaseName
            $appearanceRaceDatabaseName
            $raceDatabaseName
        )
        $destinationDatabaseNames = @(
            $databaseName
            $excludedDatabaseName
            $friendlyFailureDatabaseName
            $friendlySuccessDatabaseName
            $exceptionFailureDatabaseName
            $exceptionNotRunDatabaseName
            $importFailureDatabaseName
            $publishFailureDatabaseName
            $appearanceRaceDatabaseName
            $appearanceRacerDatabaseName
            $raceDatabaseName
            $replacementRacerDatabaseName
        )
        $testPath = "/tmp/dbatools-azmigration-$suffix"
        $destinationConnectionString = "Server=dbatoolstestmigration.database.windows.net;Authentication=Active Directory Service Principal;Database=master;User Id=$env:CLIENTID;Password=$env:CLIENTSECRET;Encrypt=True;TrustServerCertificate=False;"
        $sourceServer = $null
        $destinationMaster = $null
        $verificationServer = $null
        $raceJob = $null
        $retainedBacpacPath = $null
        $primaryError = $null
        $cleanupErrors = @()

        try {
            $splatNewTestPath = @{
                Path     = $testPath
                ItemType = "Directory"
                Force    = $true
            }
            $null = New-Item @splatNewTestPath
            $splatSourceConnection = @{
                SqlInstance   = "localhost"
                SqlCredential = $sourceCredential
                Database      = "master"
            }
            $sourceServer = Connect-DbaInstance @splatSourceConnection
            $splatGetSourceDatabases = @{
                SqlInstance     = $sourceServer
                ExcludeSystem   = $true
                OnlyAccessible  = $true
                EnableException = $true
            }
            $sourceDatabasesBefore = @(Get-DbaDatabase @splatGetSourceDatabases)

            foreach ($sourceDatabaseName in $sourceDatabaseNames) {
                $splatNewSourceDatabase = @{
                    SqlInstance     = $sourceServer
                    Name            = $sourceDatabaseName
                    EnableException = $true
                }
                $null = New-DbaDatabase @splatNewSourceDatabase
            }

            $validDatabaseNames = @(
                $databaseName
                $excludedDatabaseName
                $friendlySuccessDatabaseName
                $exceptionNotRunDatabaseName
                $importFailureDatabaseName
            )
            $proofQuery = @"
CREATE TABLE dbo.MigrationProof
(
    Id int NOT NULL PRIMARY KEY,
    Value int NOT NULL
);
INSERT dbo.MigrationProof (Id, Value)
VALUES (1, 10), (2, 20), (3, 30);
"@
            foreach ($validDatabaseName in $validDatabaseNames) {
                $splatProofQuery = @{
                    SqlInstance     = $sourceServer
                    Database        = $validDatabaseName
                    Query           = $proofQuery
                    EnableException = $true
                }
                $null = Invoke-DbaQuery @splatProofQuery
            }

            $encryptedProcedureQuery = "CREATE PROCEDURE dbo.EncryptedProof WITH ENCRYPTION AS SELECT 1 AS Value;"
            foreach ($failureDatabaseName in @($friendlyFailureDatabaseName, $exceptionFailureDatabaseName)) {
                $splatEncryptedProcedure = @{
                    SqlInstance     = $sourceServer
                    Database        = $failureDatabaseName
                    Query           = $encryptedProcedureQuery
                    EnableException = $true
                }
                $null = Invoke-DbaQuery @splatEncryptedProcedure
            }

            $raceProofQuery = @"
CREATE TABLE dbo.MigrationProof
(
    Id int NOT NULL PRIMARY KEY,
    Value int NOT NULL,
    Payload varchar(200) NOT NULL
);
WITH Numbers AS
(
    SELECT TOP (200000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Id
    FROM sys.all_objects AS first_set
    CROSS JOIN sys.all_objects AS second_set
)
INSERT dbo.MigrationProof (Id, Value, Payload)
SELECT Id, Id, CONVERT(varchar(36), NEWID()) + REPLICATE(CONVERT(varchar(36), NEWID()), 4)
FROM Numbers;
"@
            foreach ($largeRaceDatabaseName in @($appearanceRaceDatabaseName, $raceDatabaseName)) {
                $splatRaceProof = @{
                    SqlInstance     = $sourceServer
                    Database        = $largeRaceDatabaseName
                    Query           = $raceProofQuery
                    EnableException = $true
                }
                $null = Invoke-DbaQuery @splatRaceProof
            }

            $importOptions = New-DbaDacOption -Type "Bacpac" -Action "Publish"
            $importOptions.DatabaseSpecification.Edition = "Basic"
            $importOptions.DatabaseSpecification.ServiceObjective = "Basic"
            $importOptions.DatabaseSpecification.MaximumSize = 1

            $migrationSplat = @{
                Source          = $sourceServer
                Destination     = $destinationConnectionString
                Database        = $databaseName
                Path            = $testPath
                ImportDacOption = $importOptions
                EnableException = $true
                Confirm         = $false
            }

            $missingMigrationSplat = $migrationSplat.Clone()
            $missingMigrationSplat.Database = "${databaseName}_missing"
            { Start-DbaAzMigration @missingMigrationSplat } | Should -Throw "*not found or are not accessible*"

            $whatIfResult = Start-DbaAzMigration @migrationSplat -WhatIf
            $whatIfResult | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $testPath -Filter "*.bacpac") | Should -BeNullOrEmpty

            $allDatabaseSplat = $migrationSplat.Clone()
            $null = $allDatabaseSplat.Remove("Database")
            $allDatabaseSplat.ExcludeDatabase = @($sourceDatabasesBefore.Name) + @($sourceDatabaseNames | Where-Object { $PSItem -ne $databaseName })
            $initialRecords = @(Start-DbaAzMigration @allDatabaseSplat -Verbose 4>&1)
            $migrationVerbose = @($initialRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] })
            $initialResult = @($initialRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $initialResult.Count | Should -Be 1
            $initialResult.Status | Should -Be "Successful"
            $initialResult.Type | Should -Be "Database"
            $initialResult.Name | Should -Be $databaseName
            $initialResult.DestinationDatabase | Should -Be $databaseName
            $initialResult[0].PSObject.TypeNames | Should -Contain "dbatools.MigrationObject"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "SourceServer"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "DestinationServer"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "Notes"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "DateTime"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "BacpacPath"
            $initialResult[0].PSObject.Properties.Name | Should -Contain "Elapsed"
            Test-Path -LiteralPath $initialResult.BacpacPath | Should -BeFalse
            $verboseText = $migrationVerbose.Message -join [Environment]::NewLine
            $verboseText | Should -Not -Match ([regex]::Escape("dbatools.IO"))
            $verboseText | Should -Not -Match ([regex]::Escape($env:CLIENTSECRET))

            $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
            $splatGetExcludedDestination = @{
                SqlInstance     = $destinationMaster
                Database        = $excludedDatabaseName
                EnableException = $true
            }
            Get-DbaDatabase @splatGetExcludedDestination | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $destinationMaster
            $destinationMaster = $null

            $verificationConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$databaseName")
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $splatVerifyRows = @{
                SqlInstance     = $verificationServer
                Database        = $databaseName
                Query           = "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id"
                EnableException = $true
            }
            $rows = Invoke-DbaQuery @splatVerifyRows
            ($rows.Id -join ",") | Should -Be "1,2,3"
            ($rows.Value -join ",") | Should -Be "10,20,30"

            $splatChangeProof = @{
                SqlInstance     = $verificationServer
                Database        = $databaseName
                Query           = "UPDATE dbo.MigrationProof SET Value = 999 WHERE Id = 1"
                EnableException = $true
            }
            $null = Invoke-DbaQuery @splatChangeProof
            $skippedResult = Start-DbaAzMigration @migrationSplat
            $skippedResult.Status | Should -Be "Skipped"
            $skippedResult.Notes | Should -Be "Already exists on destination"
            $splatVerifyUnchanged = @{
                SqlInstance     = $verificationServer
                Database        = $databaseName
                Query           = "SELECT Value FROM dbo.MigrationProof WHERE Id = 1"
                EnableException = $true
            }
            $unchangedValue = Invoke-DbaQuery @splatVerifyUnchanged
            $unchangedValue.Value | Should -Be 999

            $null = Disconnect-DbaInstance -InputObject $verificationServer
            $verificationServer = $null
            $forcedResult = Start-DbaAzMigration @migrationSplat -Force
            $forcedResult.Status | Should -Be "Successful"
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $splatVerifyRows.SqlInstance = $verificationServer
            $forcedRows = Invoke-DbaQuery @splatVerifyRows
            ($forcedRows.Id -join ",") | Should -Be "1,2,3"
            ($forcedRows.Value -join ",") | Should -Be "10,20,30"

            $null = Disconnect-DbaInstance -InputObject $verificationServer
            $verificationServer = $null
            $retainedResult = Start-DbaAzMigration @migrationSplat -Force -KeepBacpac
            $retainedResult.Status | Should -Be "Successful"
            $retainedBacpacPath = $retainedResult.BacpacPath
            Test-Path -LiteralPath $retainedBacpacPath | Should -BeTrue
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $splatVerifyRows.SqlInstance = $verificationServer
            $retainedRows = Invoke-DbaQuery @splatVerifyRows
            ($retainedRows.Value -join ",") | Should -Be "10,20,30"
            $null = Disconnect-DbaInstance -InputObject $verificationServer
            $verificationServer = $null

            $friendlySplat = $migrationSplat.Clone()
            $null = $friendlySplat.Remove("EnableException")
            $friendlySplat.Database = @($friendlyFailureDatabaseName, $friendlySuccessDatabaseName)
            $friendlyResults = @(Start-DbaAzMigration @friendlySplat)
            $friendlyResults.Count | Should -Be 2
            ($friendlyResults | Where-Object Name -EQ $friendlyFailureDatabaseName).Status | Should -Be "Failed"
            ($friendlyResults | Where-Object Name -EQ $friendlySuccessDatabaseName).Status | Should -Be "Successful"

            $exceptionSplat = $migrationSplat.Clone()
            $exceptionSplat.Database = @($exceptionFailureDatabaseName, $exceptionNotRunDatabaseName)
            { Start-DbaAzMigration @exceptionSplat } | Should -Throw "*BACPAC export failed*"
            $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
            $splatGetExceptionDestination = @{
                SqlInstance     = $destinationMaster
                Database        = $exceptionNotRunDatabaseName
                EnableException = $true
            }
            Get-DbaDatabase @splatGetExceptionDestination | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $destinationMaster
            $destinationMaster = $null

            $invalidImportOptions = New-DbaDacOption -Type "Bacpac" -Action "Publish"
            $invalidImportOptions.DatabaseSpecification.Edition = "Basic"
            $invalidImportOptions.DatabaseSpecification.ServiceObjective = "DefinitelyInvalid"
            $invalidImportOptions.DatabaseSpecification.MaximumSize = 1
            $invalidImportSplat = $migrationSplat.Clone()
            $invalidImportSplat.Database = $importFailureDatabaseName
            $invalidImportSplat.ImportDacOption = $invalidImportOptions
            { Start-DbaAzMigration @invalidImportSplat } | Should -Throw "*BACPAC import failed*"

            $publishFailureOutput = New-Object System.Collections.ArrayList
            $publishFailureRecord = $null
            $splatDirectPublishFailure = @{
                ConnectionString = $destinationConnectionString
                Database         = $publishFailureDatabaseName
                Path             = $retainedBacpacPath
                DacOption        = $invalidImportOptions
                Type             = "Bacpac"
                EnableException  = $true
                Confirm          = $false
            }
            try {
                Publish-DbaDacPackage @splatDirectPublishFailure | ForEach-Object {
                    $null = $publishFailureOutput.Add($PSItem)
                }
            } catch {
                $publishFailureRecord = $PSItem
            }
            $publishFailureRecord | Should -Not -BeNullOrEmpty
            $publishFailureOutput | Should -BeNullOrEmpty

            $modulePath = (Resolve-Path "./dbatools.psd1").Path
            $raceScript = {
                param($ModulePath, [PSCredential]$SourceSqlCredential, $ConnectionString, $DatabaseName, $PackagePath, $ReplaceExisting)

                Import-Module $ModulePath -Force
                $jobImportOptions = New-DbaDacOption -Type "Bacpac" -Action "Publish"
                $jobImportOptions.DatabaseSpecification.Edition = "Basic"
                $jobImportOptions.DatabaseSpecification.ServiceObjective = "Basic"
                $jobImportOptions.DatabaseSpecification.MaximumSize = 1
                $splatJobMigration = @{
                    Source                  = "localhost"
                    Destination             = $ConnectionString
                    SourceSqlCredential     = $SourceSqlCredential
                    Database                = $DatabaseName
                    Path                    = $PackagePath
                    ImportDacOption         = $jobImportOptions
                    Confirm                 = $false
                    EnableException         = $true
                    Verbose                 = $true
                }
                if ($ReplaceExisting) {
                    $splatJobMigration.Force = $true
                }
                Start-DbaAzMigration @splatJobMigration *>&1
            }
            $raceCases = @(
                [pscustomobject]@{
                    DatabaseName      = $appearanceRaceDatabaseName
                    RacerDatabaseName = $appearanceRacerDatabaseName
                    ReplaceExisting   = $false
                    ExpectedFailure   = "*appeared while the BACPAC was being imported*"
                }
                [pscustomobject]@{
                    DatabaseName      = $raceDatabaseName
                    RacerDatabaseName = $replacementRacerDatabaseName
                    ReplaceExisting   = $true
                    ExpectedFailure   = "*was replaced while the BACPAC was being imported*"
                }
            )
            foreach ($raceCase in $raceCases) {
                $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
                $racePreparationDatabaseNames = @($raceCase.RacerDatabaseName)
                if ($raceCase.ReplaceExisting) {
                    $racePreparationDatabaseNames += $raceCase.DatabaseName
                }
                foreach ($racePreparationDatabaseName in $racePreparationDatabaseNames) {
                    $splatCreateRacePreparationDatabase = @{
                        SqlInstance     = $destinationMaster
                        Database        = "master"
                        Query           = "CREATE DATABASE [$racePreparationDatabaseName] (EDITION = 'Basic', SERVICE_OBJECTIVE = 'Basic', MAXSIZE = 1 GB);"
                        EnableException = $true
                    }
                    $null = Invoke-DbaQuery @splatCreateRacePreparationDatabase
                }
                $null = Disconnect-DbaInstance -InputObject $destinationMaster
                $destinationMaster = $null

                $splatRaceJob = @{
                    ScriptBlock  = $raceScript
                    ArgumentList = @($modulePath, $sourceCredential, $destinationConnectionString, $raceCase.DatabaseName, $testPath, $raceCase.ReplaceExisting)
                }
                $raceJob = Start-Job @splatRaceJob
                $raceSignalDeadline = (Get-Date).AddMinutes(5)
                $raceSignalObserved = $false
                do {
                    $splatReadRaceSignal = @{
                        Job         = $raceJob
                        Keep        = $true
                        ErrorAction = "SilentlyContinue"
                    }
                    $raceJobOutput = @(Receive-Job @splatReadRaceSignal)
                    $raceSignalObserved = @($raceJobOutput | Where-Object { $PSItem.ToString() -like "*Destination state captured for $($raceCase.DatabaseName). Starting BACPAC export.*" }).Count -gt 0
                    if (-not $raceSignalObserved -and $raceJob.State -in @("Running", "NotStarted")) {
                        Start-Sleep -Milliseconds 50
                    }
                } while (-not $raceSignalObserved -and $raceJob.State -in @("Running", "NotStarted") -and (Get-Date) -lt $raceSignalDeadline)
                if (-not $raceSignalObserved) {
                    throw "The race test did not observe the post-destination-check export signal. Job state: $($raceJob.State)."
                }

                $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
                if ($raceCase.ReplaceExisting) {
                    $splatGetRaceDatabase = @{
                        SqlInstance     = $destinationMaster
                        Database        = $raceCase.DatabaseName
                        EnableException = $true
                    }
                    $initialRaceDatabase = Get-DbaDatabase @splatGetRaceDatabase
                    if (-not $initialRaceDatabase) {
                        throw "The Force race test could not find its initial destination database."
                    }
                    $splatRemoveInitialRaceDatabase = @{
                        InputObject     = $initialRaceDatabase
                        Confirm         = $false
                        EnableException = $true
                    }
                    $null = Remove-DbaDatabase @splatRemoveInitialRaceDatabase
                }

                $destinationMaster.Databases.Refresh()
                $splatGetRacerDatabase = @{
                    SqlInstance     = $destinationMaster
                    Database        = $raceCase.RacerDatabaseName
                    EnableException = $true
                }
                $racerDatabase = Get-DbaDatabase @splatGetRacerDatabase
                if (-not $racerDatabase) {
                    throw "The race test could not find its pre-created racer database."
                }
                $racerDatabase.Rename($raceCase.DatabaseName)
                $null = Disconnect-DbaInstance -InputObject $destinationMaster
                $destinationMaster = $null

                $null = Wait-Job -Job $raceJob -Timeout 900
                if ($raceJob.State -in @("Running", "NotStarted")) {
                    throw "The race migration job did not complete before timeout."
                }
                $raceFailure = $raceJob.ChildJobs[0].JobStateInfo.Reason
                $null = Receive-Job -Job $raceJob -ErrorAction SilentlyContinue
                Remove-Job -Job $raceJob -Force
                $raceJob = $null
                $raceFailure | Should -Not -BeNullOrEmpty
                $raceFailure.Message | Should -BeLike $raceCase.ExpectedFailure

                $raceConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$($raceCase.DatabaseName)")
                $verificationServer = Connect-DbaInstance -SqlInstance $raceConnectionString
                $splatVerifyRaceDatabase = @{
                    SqlInstance     = $verificationServer
                    Database        = $raceCase.DatabaseName
                    Query           = "SELECT OBJECT_ID('dbo.MigrationProof') AS MigrationProofObjectId"
                    EnableException = $true
                }
                $raceProof = Invoke-DbaQuery @splatVerifyRaceDatabase
                $raceProof.MigrationProofObjectId | Should -BeNullOrEmpty
                $null = Disconnect-DbaInstance -InputObject $verificationServer
                $verificationServer = $null
            }

            $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
            $remainingRunStagingDatabases = @(Get-DbaDatabase -SqlInstance $destinationMaster -EnableException | Where-Object Name -Like "dbatools_azmigration_*${suffix}*")
            $remainingRunStagingDatabases | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $destinationMaster
            $destinationMaster = $null
        } catch {
            $primaryError = $PSItem
        } finally {
            if ($raceJob) {
                try {
                    $splatStopRaceJob = @{
                        Job         = $raceJob
                        ErrorAction = "Stop"
                    }
                    Stop-Job @splatStopRaceJob
                    $splatRemoveRaceJob = @{
                        Job         = $raceJob
                        Force       = $true
                        ErrorAction = "Stop"
                    }
                    Remove-Job @splatRemoveRaceJob
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if ($verificationServer) {
                try {
                    $null = Disconnect-DbaInstance -InputObject $verificationServer
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if ($destinationMaster) {
                try {
                    $null = Disconnect-DbaInstance -InputObject $destinationMaster
                } catch {
                    $cleanupErrors += $PSItem
                }
                $destinationMaster = $null
            }

            try {
                $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
                $runDestinationDatabases = @(Get-DbaDatabase -SqlInstance $destinationMaster -EnableException | Where-Object {
                        $PSItem.Name -in $destinationDatabaseNames -or $PSItem.Name -like "dbatools_azmigration_*${suffix}*"
                    })
                foreach ($runDestinationDatabase in $runDestinationDatabases) {
                    try {
                        $splatRemoveDestination = @{
                            InputObject     = $runDestinationDatabase
                            Confirm         = $false
                            EnableException = $true
                        }
                        $null = Remove-DbaDatabase @splatRemoveDestination
                    } catch {
                        $cleanupErrors += $PSItem
                    }
                }
                $destinationMaster.Databases.Refresh()
                $remainingDestinationDatabases = @(Get-DbaDatabase -SqlInstance $destinationMaster -EnableException | Where-Object {
                        $PSItem.Name -in $destinationDatabaseNames -or $PSItem.Name -like "dbatools_azmigration_*${suffix}*"
                    })
                if ($remainingDestinationDatabases) {
                    throw "Azure cleanup did not drop: $($remainingDestinationDatabases.Name -join ", ")."
                }
            } catch {
                $cleanupErrors += $PSItem
            } finally {
                if ($destinationMaster) {
                    try {
                        $null = Disconnect-DbaInstance -InputObject $destinationMaster
                    } catch {
                        $cleanupErrors += $PSItem
                    }
                }
            }

            if ($sourceServer) {
                foreach ($sourceDatabaseName in $sourceDatabaseNames) {
                    try {
                        $splatGetSourceDatabase = @{
                            SqlInstance     = $sourceServer
                            Database        = $sourceDatabaseName
                            EnableException = $true
                        }
                        $sourceDatabase = Get-DbaDatabase @splatGetSourceDatabase
                        if ($sourceDatabase) {
                            $splatRemoveSourceDatabase = @{
                                InputObject     = $sourceDatabase
                                Confirm         = $false
                                EnableException = $true
                            }
                            $null = Remove-DbaDatabase @splatRemoveSourceDatabase
                        }
                    } catch {
                        $cleanupErrors += $PSItem
                    }
                }
                try {
                    $sourceServer.Databases.Refresh()
                    $splatGetRemainingSourceDatabases = @{
                        SqlInstance     = $sourceServer
                        Database        = $sourceDatabaseNames
                        EnableException = $true
                    }
                    $remainingSourceDatabases = @(Get-DbaDatabase @splatGetRemainingSourceDatabases)
                    if ($remainingSourceDatabases) {
                        throw "Source cleanup did not drop: $($remainingSourceDatabases.Name -join ", ")."
                    }
                } catch {
                    $cleanupErrors += $PSItem
                }
                try {
                    $null = Disconnect-DbaInstance -InputObject $sourceServer
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if ($retainedBacpacPath -and (Test-Path -LiteralPath $retainedBacpacPath)) {
                try {
                    $splatRemoveRetainedBacpac = @{
                        LiteralPath = $retainedBacpacPath
                        Force       = $true
                        ErrorAction = "Stop"
                    }
                    Remove-Item @splatRemoveRetainedBacpac
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if (Test-Path -LiteralPath $testPath) {
                try {
                    $splatRemoveTestPath = @{
                        LiteralPath = $testPath
                        Recurse     = $true
                        Force       = $true
                        ErrorAction = "Stop"
                    }
                    Remove-Item @splatRemoveTestPath
                } catch {
                    $cleanupErrors += $PSItem
                }
            }
        }

        if ($primaryError -or $cleanupErrors.Count -gt 0) {
            $failureMessages = @()
            if ($primaryError) {
                $failureMessages += "Test failure: $($primaryError.Exception.Message)"
            }
            if ($cleanupErrors.Count -gt 0) {
                $failureMessages += "Cleanup failure: $($cleanupErrors.Exception.Message -join "; ")"
            }
            throw ($failureMessages -join [Environment]::NewLine)
        }
    }
}
