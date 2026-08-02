#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaAzMigration"
)

BeforeDiscovery {
    $script:raceTestCases = @(
        @{ Name = "an absent final name appears before promotion"; Scenario = "Appearance" }
        @{ Name = "an existing final name is replaced before promotion"; Scenario = "Replacement" }
        @{ Name = "an existing final name is replaced immediately before rename"; Scenario = "PromotionReplacement" }
        @{ Name = "an owned staging database is replaced immediately before cleanup"; Scenario = "StagingReplacement" }
    )
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $env:AZMIGRATION_ACCESS_TOKEN) {
            throw "Start-DbaAzMigration Azure integration requires AZMIGRATION_ACCESS_TOKEN from an authenticated Azure CLI session."
        }

        $sourcePassword = New-Object System.Security.SecureString
        foreach ($sourcePasswordCharacter in "dbatools.IO".ToCharArray()) {
            $sourcePassword.AppendChar($sourcePasswordCharacter)
        }
        $sourcePassword.MakeReadOnly()
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
        $promotionRaceDatabaseName = "dbatoolsci_azpromote_$suffix"
        $promotionRacerDatabaseName = "dbatoolsci_azpromote_racer_$suffix"
        $stagingCleanupRaceDatabaseName = "dbatoolsci_azstage_$suffix"
        $stagingCleanupFinalRacerDatabaseName = "dbatoolsci_azstage_final_$suffix"
        $stagingCleanupReplacementDatabaseName = "dbatoolsci_azstage_replacement_$suffix"
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
            $promotionRaceDatabaseName
            $stagingCleanupRaceDatabaseName
        )
        $script:destinationDatabaseNames = @(
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
            $promotionRaceDatabaseName
            $promotionRacerDatabaseName
            $stagingCleanupRaceDatabaseName
            $stagingCleanupFinalRacerDatabaseName
            $stagingCleanupReplacementDatabaseName
        )
        $testPath = "/tmp/dbatools-azmigration-$suffix"
        $destinationServerName = if ($env:DBATOOLS_AZMIGRATION_SERVER) { $env:DBATOOLS_AZMIGRATION_SERVER } else { "dbatools" }
        $destinationConnectionString = "Server=$destinationServerName.database.windows.net;Database=master;Encrypt=True;TrustServerCertificate=False;"
        $script:destinationAccessToken = $env:AZMIGRATION_ACCESS_TOKEN
        $script:verificationConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$databaseName")
        $sourceServer = $null
        $script:destinationMaster = $null
        $script:verificationServer = $null
        $script:raceJob = $null
        $script:retainedBacpacPaths = New-Object System.Collections.ArrayList

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
        $script:sourceDatabasesBefore = @(Get-DbaDatabase @splatGetSourceDatabases)

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
    SELECT TOP (100)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Id
    FROM sys.all_objects AS first_set
    CROSS JOIN sys.all_objects AS second_set
)
INSERT dbo.MigrationProof (Id, Value, Payload)
SELECT Id, Id, CONVERT(varchar(36), NEWID()) + REPLICATE(CONVERT(varchar(36), NEWID()), 4)
FROM Numbers;
"@
        foreach ($largeRaceDatabaseName in @($appearanceRaceDatabaseName, $raceDatabaseName, $promotionRaceDatabaseName, $stagingCleanupRaceDatabaseName)) {
            $splatRaceProof = @{
                SqlInstance     = $sourceServer
                Database        = $largeRaceDatabaseName
                Query           = $raceProofQuery
                EnableException = $true
            }
            $null = Invoke-DbaQuery @splatRaceProof
        }

        $importOptions = New-DbaDacOption -Type Bacpac -Action Publish
        $importOptions.DatabaseSpecification.Edition = "Basic"
        $importOptions.DatabaseSpecification.ServiceObjective = "Basic"
        $importOptions.DatabaseSpecification.MaximumSize = 1

        $script:splatBaseMigration = @{
            Source                 = $sourceServer
            Destination            = $destinationConnectionString
            DestinationAccessToken = $script:destinationAccessToken
            Database               = $databaseName
            Path                   = $testPath
            ImportDacOption        = $importOptions
            EnableException        = $true
            Confirm                = $false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Selection and successful migration" {
        It "rejects a requested database that is not accessible" {
            $splatMissingMigration = $script:splatBaseMigration.Clone()
            $splatMissingMigration.Database = "${databaseName}_missing"
            { Start-DbaAzMigration @splatMissingMigration } | Should -Throw "*not found or are not accessible*"
        }

        It "honors WhatIf without creating a package or destination database" {
            $whatIfResult = Start-DbaAzMigration @splatBaseMigration -WhatIf
            $whatIfResult | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $testPath -Filter "*.bacpac") | Should -BeNullOrEmpty

            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            Get-DbaDatabase -SqlInstance $script:destinationMaster -Database $databaseName | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null
        }

        It "selects the included database, migrates its rows, returns the output contract, and emits no secrets" {
            $splatAllDatabasesMigration = $script:splatBaseMigration.Clone()
            $null = $splatAllDatabasesMigration.Remove("Database")
            $splatAllDatabasesMigration.ExcludeDatabase = @($script:sourceDatabasesBefore.Name) + @($sourceDatabaseNames | Where-Object { $PSItem -ne $databaseName })
            $initialRecords = @(Start-DbaAzMigration @splatAllDatabasesMigration -Verbose 4>&1)
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
            $verboseText.Contains("dbatools.IO") | Should -BeFalse
            $verboseText.Contains($env:CLIENTSECRET) | Should -BeFalse
            $verboseText.Contains($script:destinationAccessToken) | Should -BeFalse
            $verboseText | Should -Not -Match "Using connection string"

            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $splatGetExcludedDestination = @{
                SqlInstance     = $script:destinationMaster
                Database        = $excludedDatabaseName
                EnableException = $true
            }
            Get-DbaDatabase @splatGetExcludedDestination | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null

            $script:verificationServer = Connect-DbaInstance -SqlInstance $script:verificationConnectionString -AccessToken $script:destinationAccessToken
            $splatVerifyRows = @{
                SqlInstance     = $script:verificationServer
                Database        = $databaseName
                Query           = "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id"
                EnableException = $true
            }
            $rows = Invoke-DbaQuery @splatVerifyRows
            ($rows.Id -join ",") | Should -Be "1,2,3"
            ($rows.Value -join ",") | Should -Be "10,20,30"
            $null = Disconnect-DbaInstance -InputObject $script:verificationServer
            $script:verificationServer = $null
        }
    }

    Context "Existing destination handling" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Start-DbaAzMigration @splatBaseMigration
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "skips an existing destination without modifying it" {
            $script:verificationServer = Connect-DbaInstance -SqlInstance $script:verificationConnectionString -AccessToken $script:destinationAccessToken
            $splatChangeProof = @{
                SqlInstance     = $script:verificationServer
                Database        = $databaseName
                Query           = "UPDATE dbo.MigrationProof SET Value = 999 WHERE Id = 1"
                EnableException = $true
            }
            $null = Invoke-DbaQuery @splatChangeProof
            $skippedResult = Start-DbaAzMigration @splatBaseMigration
            $skippedResult.Status | Should -Be "Skipped"
            $skippedResult.Notes | Should -Be "Already exists on destination"
            $splatVerifyUnchanged = @{
                SqlInstance     = $script:verificationServer
                Database        = $databaseName
                Query           = "SELECT Value FROM dbo.MigrationProof WHERE Id = 1"
                EnableException = $true
            }
            $unchangedValue = Invoke-DbaQuery @splatVerifyUnchanged
            $unchangedValue.Value | Should -Be 999

            $null = Disconnect-DbaInstance -InputObject $script:verificationServer
            $script:verificationServer = $null
        }

        It "force replaces an existing destination with the source rows" {
            $forcedResult = Start-DbaAzMigration @splatBaseMigration -Force
            $forcedResult.Status | Should -Be "Successful"
            $script:verificationServer = Connect-DbaInstance -SqlInstance $script:verificationConnectionString -AccessToken $script:destinationAccessToken
            $splatVerifyReplacementRows = @{
                SqlInstance     = $script:verificationServer
                Database        = $databaseName
                Query           = "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id"
                EnableException = $true
            }
            $forcedRows = Invoke-DbaQuery @splatVerifyReplacementRows
            ($forcedRows.Id -join ",") | Should -Be "1,2,3"
            ($forcedRows.Value -join ",") | Should -Be "10,20,30"

            $null = Disconnect-DbaInstance -InputObject $script:verificationServer
            $script:verificationServer = $null
        }

        It "retains the generated BACPAC when requested" {
            $retainedResult = Start-DbaAzMigration @splatBaseMigration -Force -KeepBacpac
            $retainedResult.Status | Should -Be "Successful"
            $retainedBacpacPath = $retainedResult.BacpacPath
            $null = $script:retainedBacpacPaths.Add($retainedBacpacPath)
            Test-Path -LiteralPath $retainedBacpacPath | Should -BeTrue
        }
    }

    Context "Failure semantics" {
        It "continues to the next database after a friendly-mode export failure" {
            $splatFriendlyMigration = $script:splatBaseMigration.Clone()
            $null = $splatFriendlyMigration.Remove("EnableException")
            $splatFriendlyMigration.Database = @($friendlyFailureDatabaseName, $friendlySuccessDatabaseName)
            $friendlyResults = @(Start-DbaAzMigration @splatFriendlyMigration)
            $friendlyResults.Count | Should -Be 2
            $friendlyFailedResult = $friendlyResults | Where-Object Name -EQ $friendlyFailureDatabaseName
            $friendlyFailedResult.Status | Should -Be "Failed"
            $friendlyFailedResult.BacpacPath | Should -BeNullOrEmpty
            ($friendlyResults | Where-Object Name -EQ $friendlySuccessDatabaseName).Status | Should -Be "Successful"
        }

        It "stops after the first export failure in exception mode" {
            $splatExceptionMigration = $script:splatBaseMigration.Clone()
            $splatExceptionMigration.Database = @($exceptionFailureDatabaseName, $exceptionNotRunDatabaseName)
            { Start-DbaAzMigration @splatExceptionMigration } | Should -Throw "*BACPAC export failed*"
            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $splatGetExceptionDestination = @{
                SqlInstance     = $script:destinationMaster
                Database        = $exceptionNotRunDatabaseName
                EnableException = $true
            }
            Get-DbaDatabase @splatGetExceptionDestination | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null
        }

        It "reports an induced BACPAC import failure" {
            $invalidImportOptions = New-DbaDacOption -Type Bacpac -Action Publish
            $invalidImportOptions.DatabaseSpecification.Edition = "Basic"
            $invalidImportOptions.DatabaseSpecification.ServiceObjective = "DefinitelyInvalid"
            $invalidImportOptions.DatabaseSpecification.MaximumSize = 1
            $splatInvalidImportMigration = $script:splatBaseMigration.Clone()
            $splatInvalidImportMigration.Database = $importFailureDatabaseName
            $splatInvalidImportMigration.ImportDacOption = $invalidImportOptions
            { Start-DbaAzMigration @splatInvalidImportMigration } | Should -Throw "*BACPAC import failed*"
            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $failedImportStagingPattern = "dbatools_azmigration_${importFailureDatabaseName}_*"
            $failedImportStagingDatabases = @(Get-DbaDatabase -SqlInstance $script:destinationMaster -EnableException | Where-Object Name -Like $failedImportStagingPattern)
            $failedImportStagingDatabases | Should -BeNullOrEmpty
            $splatGetFailedImportDestination = @{
                SqlInstance     = $script:destinationMaster
                Database        = $importFailureDatabaseName
                EnableException = $true
            }
            Get-DbaDatabase @splatGetFailedImportDestination | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null
        }

        It "emits no success object when a direct BACPAC publish fails" {
            $invalidImportOptions = New-DbaDacOption -Type Bacpac -Action Publish
            $invalidImportOptions.DatabaseSpecification.Edition = "Basic"
            $invalidImportOptions.DatabaseSpecification.ServiceObjective = "DefinitelyInvalid"
            $invalidImportOptions.DatabaseSpecification.MaximumSize = 1
            $publishFailureOutput = New-Object System.Collections.ArrayList
            $publishFailureRecord = $null
            $publishFailureBacpacPath = Join-Path $testPath "$publishFailureDatabaseName.bacpac"
            $splatExportPublishFailure = @{
                SqlInstance     = $sourceServer
                Database        = $databaseName
                FilePath        = $publishFailureBacpacPath
                Type            = "Bacpac"
                EnableException = $true
            }
            $publishFailurePackage = Export-DbaDacPackage @splatExportPublishFailure
            $null = $script:retainedBacpacPaths.Add($publishFailurePackage.Path)
            $splatDirectPublishFailure = @{
                ConnectionString = $destinationConnectionString
                AccessToken      = $script:destinationAccessToken
                Database         = $publishFailureDatabaseName
                Path             = $publishFailurePackage.Path
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
        }
    }

    Context "Destination race safety" {
        AfterEach {
            if ($script:raceJob) {
                Stop-Job -Job $script:raceJob -ErrorAction SilentlyContinue
                Remove-Job -Job $script:raceJob -Force -ErrorAction SilentlyContinue
                $script:raceJob = $null
            }
            if ($script:verificationServer) {
                $null = Disconnect-DbaInstance -InputObject $script:verificationServer
                $script:verificationServer = $null
            }
            if ($script:destinationMaster) {
                $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
                $script:destinationMaster = $null
            }
        }

        It "preserves destination ownership when <Name>" -ForEach $script:raceTestCases {
            $modulePath = (Resolve-Path "./dbatools.psd1").Path
            $raceScript = {
                param($ModulePath, [PSCredential]$SourceSqlCredential, $ConnectionString, $DestinationAccessToken, $DatabaseName, $PackagePath, $ReplaceExisting, $BarrierText, $BarrierReadyPath, $BarrierReleasePath, $SecondBarrierText, $SecondBarrierReadyPath, $SecondBarrierReleasePath)

                Import-Module $ModulePath -Force
                $commandPath = Join-Path (Split-Path -Path $ModulePath) "public/Start-DbaAzMigration.ps1"
                $barrierMatch = Select-String -LiteralPath $commandPath -SimpleMatch $BarrierText | Select-Object -First 1
                if (-not $barrierMatch) {
                    throw "The race test could not locate its promotion barrier in Start-DbaAzMigration."
                }
                $env:DBATOOLS_AZMIGRATION_BARRIER_READY_PATH = $BarrierReadyPath
                $env:DBATOOLS_AZMIGRATION_BARRIER_RELEASE_PATH = $BarrierReleasePath
                $barrierAction = {
                    Set-Content -LiteralPath $env:DBATOOLS_AZMIGRATION_BARRIER_READY_PATH -Value "ready"
                    $promotionBarrierDeadline = (Get-Date).AddMinutes(5)
                    while (-not (Test-Path -LiteralPath $env:DBATOOLS_AZMIGRATION_BARRIER_RELEASE_PATH) -and (Get-Date) -lt $promotionBarrierDeadline) {
                        Start-Sleep -Milliseconds 50
                    }
                    if (-not (Test-Path -LiteralPath $env:DBATOOLS_AZMIGRATION_BARRIER_RELEASE_PATH)) {
                        throw "The race test promotion barrier was not released before timeout."
                    }
                }
                $splatPromotionBreakpoint = @{
                    Script = $commandPath
                    Line   = $barrierMatch.LineNumber
                    Action = $barrierAction
                }
                $null = Set-PSBreakpoint @splatPromotionBreakpoint
                if ($SecondBarrierText) {
                    $secondBarrierMatch = Select-String -LiteralPath $commandPath -SimpleMatch $SecondBarrierText | Select-Object -First 1
                    if (-not $secondBarrierMatch) {
                        throw "The race test could not locate its cleanup barrier in Start-DbaAzMigration."
                    }
                    $env:DBATOOLS_AZMIGRATION_SECOND_BARRIER_READY_PATH = $SecondBarrierReadyPath
                    $env:DBATOOLS_AZMIGRATION_SECOND_BARRIER_RELEASE_PATH = $SecondBarrierReleasePath
                    $secondBarrierAction = {
                        Set-Content -LiteralPath $env:DBATOOLS_AZMIGRATION_SECOND_BARRIER_READY_PATH -Value "ready"
                        $cleanupBarrierDeadline = (Get-Date).AddMinutes(5)
                        while (-not (Test-Path -LiteralPath $env:DBATOOLS_AZMIGRATION_SECOND_BARRIER_RELEASE_PATH) -and (Get-Date) -lt $cleanupBarrierDeadline) {
                            Start-Sleep -Milliseconds 50
                        }
                        if (-not (Test-Path -LiteralPath $env:DBATOOLS_AZMIGRATION_SECOND_BARRIER_RELEASE_PATH)) {
                            throw "The race test cleanup barrier was not released before timeout."
                        }
                    }
                    $splatCleanupBreakpoint = @{
                        Script = $commandPath
                        Line   = $secondBarrierMatch.LineNumber
                        Action = $secondBarrierAction
                    }
                    $null = Set-PSBreakpoint @splatCleanupBreakpoint
                }
                $jobImportOptions = New-DbaDacOption -Type Bacpac -Action Publish
                $jobImportOptions.DatabaseSpecification.Edition = "Basic"
                $jobImportOptions.DatabaseSpecification.ServiceObjective = "Basic"
                $jobImportOptions.DatabaseSpecification.MaximumSize = 1
                $splatJobMigration = @{
                    Source                 = "localhost"
                    Destination            = $ConnectionString
                    SourceSqlCredential    = $SourceSqlCredential
                    DestinationAccessToken = $DestinationAccessToken
                    Database               = $DatabaseName
                    Path                   = $PackagePath
                    ImportDacOption        = $jobImportOptions
                    Confirm                = $false
                    EnableException        = $true
                    Verbose                = $true
                }
                if ($ReplaceExisting) {
                    $splatJobMigration.Force = $true
                }
                Start-DbaAzMigration @splatJobMigration
            }
            $raceCase = switch ($Scenario) {
                "Appearance" {
                    [pscustomobject]@{
                        DatabaseName      = $appearanceRaceDatabaseName
                        RacerDatabaseName = $appearanceRacerDatabaseName
                        ReplaceExisting   = $false
                        BarrierText       = [string]::Concat("failurePhase = ", [char]34, "Destination promotion", [char]34)
                        ExpectedFailure   = "*appeared while the BACPAC was being imported*"
                    }
                }
                "Replacement" {
                    [pscustomobject]@{
                        DatabaseName      = $raceDatabaseName
                        RacerDatabaseName = $replacementRacerDatabaseName
                        ReplaceExisting   = $true
                        BarrierText       = [string]::Concat("failurePhase = ", [char]34, "Destination promotion", [char]34)
                        ExpectedFailure   = "*was replaced while the BACPAC was being imported*"
                    }
                }
                "PromotionReplacement" {
                    [pscustomobject]@{
                        DatabaseName      = $promotionRaceDatabaseName
                        RacerDatabaseName = $promotionRacerDatabaseName
                        ReplaceExisting   = $true
                        BarrierText       = "currentDestinationDatabase.Rename"
                        ExpectedFailure   = "*was replaced during forced promotion*"
                    }
                }
                "StagingReplacement" {
                    [pscustomobject]@{
                        DatabaseName                = $stagingCleanupRaceDatabaseName
                        RacerDatabaseName           = $stagingCleanupFinalRacerDatabaseName
                        StagingRacerDatabaseName    = $stagingCleanupReplacementDatabaseName
                        ReplaceExisting             = $false
                        BarrierText                 = [string]::Concat("failurePhase = ", [char]34, "Destination promotion", [char]34)
                        SecondBarrierText           = "partialStagingDatabase = Get-DbaDatabase"
                        ExpectedFailure             = "*appeared while the BACPAC was being imported*"
                        PreservesStagingReplacement = $true
                    }
                }
                default {
                    throw "Unknown race scenario $Scenario."
                }
            }
            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $racePreparationDatabaseNames = @($raceCase.RacerDatabaseName)
            if ($raceCase.StagingRacerDatabaseName) {
                $racePreparationDatabaseNames += $raceCase.StagingRacerDatabaseName
            }
            if ($raceCase.ReplaceExisting) {
                $racePreparationDatabaseNames += $raceCase.DatabaseName
            }
            foreach ($racePreparationDatabaseName in $racePreparationDatabaseNames) {
                $splatCreateRacePreparationDatabase = @{
                    SqlInstance     = $script:destinationMaster
                    Database        = "master"
                    Query           = "CREATE DATABASE [$racePreparationDatabaseName] (EDITION = 'Basic', SERVICE_OBJECTIVE = 'Basic', MAXSIZE = 1 GB);"
                    EnableException = $true
                }
                $null = Invoke-DbaQuery @splatCreateRacePreparationDatabase
            }
            $databaseIdentityQuery = "SELECT CONVERT(nvarchar(36), service_broker_guid) + '|' + CONVERT(nvarchar(11), database_id) FROM sys.databases WHERE name = @DatabaseName"
            $splatGetExpectedRaceIdentity = @{
                SqlInstance     = $script:destinationMaster
                Database        = "master"
                Query           = $databaseIdentityQuery
                SqlParameter    = @{ DatabaseName = $raceCase.RacerDatabaseName }
                As              = "SingleValue"
                EnableException = $true
            }
            $expectedRaceDatabaseIdentity = Invoke-DbaQuery @splatGetExpectedRaceIdentity
            $expectedRaceDatabaseIdentity | Should -Not -BeNullOrEmpty
            $expectedStagingRaceDatabaseIdentity = $null
            if ($raceCase.StagingRacerDatabaseName) {
                $splatGetExpectedStagingRaceIdentity = $splatGetExpectedRaceIdentity.Clone()
                $splatGetExpectedStagingRaceIdentity.SqlParameter = @{ DatabaseName = $raceCase.StagingRacerDatabaseName }
                $expectedStagingRaceDatabaseIdentity = Invoke-DbaQuery @splatGetExpectedStagingRaceIdentity
                $expectedStagingRaceDatabaseIdentity | Should -Not -BeNullOrEmpty
            }
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null

            $barrierReadyPath = Join-Path $testPath "$($raceCase.DatabaseName)-barrier-ready"
            $barrierReleasePath = Join-Path $testPath "$($raceCase.DatabaseName)-barrier-release"
            $secondBarrierReadyPath = Join-Path $testPath "$($raceCase.DatabaseName)-second-barrier-ready"
            $secondBarrierReleasePath = Join-Path $testPath "$($raceCase.DatabaseName)-second-barrier-release"
            $script:raceJobArguments = @($modulePath, $sourceCredential, $destinationConnectionString, $script:destinationAccessToken, $raceCase.DatabaseName, $testPath, $raceCase.ReplaceExisting, $raceCase.BarrierText, $barrierReadyPath, $barrierReleasePath, $raceCase.SecondBarrierText, $secondBarrierReadyPath, $secondBarrierReleasePath)
            $script:raceJob = Start-Job -ScriptBlock $raceScript -ArgumentList $script:raceJobArguments
            $raceBarrierDeadline = (Get-Date).AddMinutes(15)
            do {
                $barrierObserved = Test-Path -LiteralPath $barrierReadyPath
                if (-not $barrierObserved -and $script:raceJob.State -in @("Running", "NotStarted")) {
                    Start-Sleep -Milliseconds 50
                }
            } while (-not $barrierObserved -and $script:raceJob.State -in @("Running", "NotStarted") -and (Get-Date) -lt $raceBarrierDeadline)
            if (-not $barrierObserved) {
                throw "The race test did not reach its deterministic promotion barrier. Job state: $($script:raceJob.State)."
            }

            try {
                $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
                if ($raceCase.ReplaceExisting) {
                    $splatGetRaceDatabase = @{
                        SqlInstance     = $script:destinationMaster
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

                $script:destinationMaster.Databases.Refresh()
                $splatGetRacerDatabase = @{
                    SqlInstance     = $script:destinationMaster
                    Database        = $raceCase.RacerDatabaseName
                    EnableException = $true
                }
                $racerDatabase = Get-DbaDatabase @splatGetRacerDatabase
                if (-not $racerDatabase) {
                    throw "The race test could not find its pre-created racer database."
                }
                $racerDatabase.Rename($raceCase.DatabaseName)
            } finally {
                if ($script:destinationMaster) {
                    $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
                    $script:destinationMaster = $null
                }
                Set-Content -LiteralPath $barrierReleasePath -Value "release"
            }

            $preservedStagingDatabaseName = $null
            if ($raceCase.SecondBarrierText) {
                $secondRaceBarrierDeadline = (Get-Date).AddMinutes(5)
                do {
                    $secondBarrierObserved = Test-Path -LiteralPath $secondBarrierReadyPath
                    if (-not $secondBarrierObserved -and $script:raceJob.State -in @("Running", "NotStarted")) {
                        Start-Sleep -Milliseconds 50
                    }
                } while (-not $secondBarrierObserved -and $script:raceJob.State -in @("Running", "NotStarted") -and (Get-Date) -lt $secondRaceBarrierDeadline)
                if (-not $secondBarrierObserved) {
                    throw "The race test did not reach its deterministic cleanup barrier. Job state: $($script:raceJob.State)."
                }

                try {
                    $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
                    $stagingDatabasePattern = "dbatools_azmigration_$($raceCase.DatabaseName)_*"
                    $stagingCandidates = @(Get-DbaDatabase -SqlInstance $script:destinationMaster -EnableException | Where-Object Name -Like $stagingDatabasePattern)
                    $stagingCandidates.Count | Should -Be 1
                    $ownedStagingDatabase = $stagingCandidates[0]
                    $preservedStagingDatabaseName = $ownedStagingDatabase.Name
                    $splatRemoveOwnedStagingDatabase = @{
                        InputObject     = $ownedStagingDatabase
                        Confirm         = $false
                        EnableException = $true
                    }
                    $null = Remove-DbaDatabase @splatRemoveOwnedStagingDatabase
                    $script:destinationMaster.Databases.Refresh()
                    $splatGetStagingRacerDatabase = @{
                        SqlInstance     = $script:destinationMaster
                        Database        = $raceCase.StagingRacerDatabaseName
                        EnableException = $true
                    }
                    $stagingRacerDatabase = Get-DbaDatabase @splatGetStagingRacerDatabase
                    if (-not $stagingRacerDatabase) {
                        throw "The staging cleanup race test could not find its pre-created replacement database."
                    }
                    $stagingRacerDatabase.Rename($preservedStagingDatabaseName)
                } finally {
                    if ($script:destinationMaster) {
                        $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
                        $script:destinationMaster = $null
                    }
                    Set-Content -LiteralPath $secondBarrierReleasePath -Value "release"
                }
            }

            $null = Wait-Job -Job $script:raceJob -Timeout 900
            if ($script:raceJob.State -in @("Running", "NotStarted")) {
                throw "The race migration job did not complete before timeout."
            }
            $raceFailure = $script:raceJob.ChildJobs[0].JobStateInfo.Reason
            $script:raceJobErrors = @($script:raceJob.ChildJobs[0].Error)
            $script:raceJobOutput = @(Receive-Job -Job $script:raceJob -ErrorAction SilentlyContinue)
            if (-not $raceFailure -and $script:raceJobErrors.Count -gt 0) {
                $raceFailure = $script:raceJobErrors[0]
            }
            Remove-Job -Job $script:raceJob -Force
            $script:raceJob = $null
            $raceResult = @($script:raceJobOutput | Where-Object { $PSItem.PSObject.Properties["Name"] -and $PSItem.Name -eq $raceCase.DatabaseName })
            $raceResult.Count | Should -Be 1
            $raceResult.Status | Should -Be "Failed"
            $raceFailureMessage = if ($raceFailure -is [System.Management.Automation.ErrorRecord]) {
                $raceFailure.Exception.Message
            } elseif ($raceFailure) {
                $raceFailure.Message
            } else {
                $raceResult.Notes
            }
            $raceFailureMessage | Should -BeLike $raceCase.ExpectedFailure
            if ($raceCase.PreservesStagingReplacement) {
                $raceResult.Notes | Should -BeLike "*replacement was preserved*"
            }

            $raceConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$($raceCase.DatabaseName)")
            $script:verificationServer = Connect-DbaInstance -SqlInstance $raceConnectionString -AccessToken $script:destinationAccessToken
            $splatVerifyRaceDatabase = @{
                SqlInstance     = $script:verificationServer
                Database        = $raceCase.DatabaseName
                Query           = "SELECT OBJECT_ID('dbo.MigrationProof') AS MigrationProofObjectId"
                EnableException = $true
            }
            $raceProof = Invoke-DbaQuery @splatVerifyRaceDatabase
            $raceProof.MigrationProofObjectId | Should -BeOfType System.DBNull
            $splatGetActualRaceIdentity = @{
                SqlInstance     = $script:verificationServer
                Database        = $raceCase.DatabaseName
                Query           = $databaseIdentityQuery
                SqlParameter    = @{ DatabaseName = $raceCase.DatabaseName }
                As              = "SingleValue"
                EnableException = $true
            }
            $actualRaceDatabaseIdentity = Invoke-DbaQuery @splatGetActualRaceIdentity
            $actualRaceDatabaseIdentity | Should -Be $expectedRaceDatabaseIdentity
            $null = Disconnect-DbaInstance -InputObject $script:verificationServer
            $script:verificationServer = $null

            if ($preservedStagingDatabaseName) {
                $preservedStagingConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$preservedStagingDatabaseName")
                $script:verificationServer = Connect-DbaInstance -SqlInstance $preservedStagingConnectionString -AccessToken $script:destinationAccessToken
                $splatVerifyPreservedStagingDatabase = @{
                    SqlInstance     = $script:verificationServer
                    Database        = $preservedStagingDatabaseName
                    Query           = "SELECT OBJECT_ID('dbo.MigrationProof') AS MigrationProofObjectId"
                    EnableException = $true
                }
                $preservedStagingProof = Invoke-DbaQuery @splatVerifyPreservedStagingDatabase
                $preservedStagingProof.MigrationProofObjectId | Should -BeOfType System.DBNull
                $splatGetActualStagingRaceIdentity = @{
                    SqlInstance     = $script:verificationServer
                    Database        = $preservedStagingDatabaseName
                    Query           = $databaseIdentityQuery
                    SqlParameter    = @{ DatabaseName = $preservedStagingDatabaseName }
                    As              = "SingleValue"
                    EnableException = $true
                }
                $actualStagingRaceDatabaseIdentity = Invoke-DbaQuery @splatGetActualStagingRaceIdentity
                $actualStagingRaceDatabaseIdentity | Should -Be $expectedStagingRaceDatabaseIdentity
                $null = Disconnect-DbaInstance -InputObject $script:verificationServer
                $script:verificationServer = $null

                $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
                $splatGetPreservedStagingDatabase = @{
                    SqlInstance     = $script:destinationMaster
                    Database        = $preservedStagingDatabaseName
                    EnableException = $true
                }
                $preservedStagingDatabase = Get-DbaDatabase @splatGetPreservedStagingDatabase
                $splatRemovePreservedStagingDatabase = @{
                    InputObject     = $preservedStagingDatabase
                    Confirm         = $false
                    EnableException = $true
                }
                $null = Remove-DbaDatabase @splatRemovePreservedStagingDatabase
                $script:destinationMaster.Databases.Refresh()
                Get-DbaDatabase @splatGetPreservedStagingDatabase | Should -BeNullOrEmpty
                $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
                $script:destinationMaster = $null
            }

            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $caseStagingPattern = "dbatools_azmigration_$($raceCase.DatabaseName)_*"
            $remainingCaseStagingDatabases = @(Get-DbaDatabase -SqlInstance $script:destinationMaster -EnableException | Where-Object Name -Like $caseStagingPattern)
            $remainingCaseStagingDatabases | Should -BeNullOrEmpty
            $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            $script:destinationMaster = $null
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $cleanupErrors = @()
        if ($script:raceJob) {
            try {
                Stop-Job -Job $script:raceJob -ErrorAction Stop
                $splatRemoveRaceJob = @{
                    Job         = $script:raceJob
                    Force       = $true
                    ErrorAction = "Stop"
                }
                Remove-Job @splatRemoveRaceJob
            } catch {
                $cleanupErrors += $PSItem
            }
        }

        if ($script:verificationServer) {
            try {
                $null = Disconnect-DbaInstance -InputObject $script:verificationServer
            } catch {
                $cleanupErrors += $PSItem
            }
        }

        if ($script:destinationMaster) {
            try {
                $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
            } catch {
                $cleanupErrors += $PSItem
            }
            $script:destinationMaster = $null
        }

        try {
            $script:destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString -AccessToken $script:destinationAccessToken
            $runDestinationDatabases = @(Get-DbaDatabase -SqlInstance $script:destinationMaster -EnableException | Where-Object {
                    $PSItem.Name -in $script:destinationDatabaseNames -or $PSItem.Name -like "dbatools_azmigration_*${suffix}*"
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
            $script:destinationMaster.Databases.Refresh()
            $remainingDestinationDatabases = @(Get-DbaDatabase -SqlInstance $script:destinationMaster -EnableException | Where-Object {
                    $PSItem.Name -in $script:destinationDatabaseNames -or $PSItem.Name -like "dbatools_azmigration_*${suffix}*"
                })
            if ($remainingDestinationDatabases) {
                throw "Azure cleanup did not drop: $($remainingDestinationDatabases.Name -join ", ")."
            }
        } catch {
            $cleanupErrors += $PSItem
        } finally {
            if ($script:destinationMaster) {
                try {
                    $null = Disconnect-DbaInstance -InputObject $script:destinationMaster
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

        foreach ($retainedBacpacPathToRemove in @($script:retainedBacpacPaths)) {
            if ($retainedBacpacPathToRemove -and (Test-Path -LiteralPath $retainedBacpacPathToRemove)) {
                try {
                    $splatRemoveRetainedBacpac = @{
                        LiteralPath = $retainedBacpacPathToRemove
                        Force       = $true
                        ErrorAction = "Stop"
                    }
                    Remove-Item @splatRemoveRetainedBacpac
                } catch {
                    $cleanupErrors += $PSItem
                }
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

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        if ($cleanupErrors.Count -gt 0) {
            throw "Cleanup failure: $($cleanupErrors.Exception.Message -join "; ")"
        }
    }
}
