#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "", Justification = "Uses the public disposable SQL container credential from the integration workflow.")]
param()

Describe "Start-DbaAzMigration Azure SQL boundary" -Tag "IntegrationTests" {
    It "migrates, skips, replaces, and retains a BACPAC against Azure SQL Database" {
        if (-not ($env:TENANTID -and $env:CLIENTID -and $env:CLIENTSECRET)) {
            throw "Start-DbaAzMigration Azure integration requires TENANTID, CLIENTID, and CLIENTSECRET."
        }

        $sourcePassword = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $sourceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sqladmin", $sourcePassword
        $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 8)
        $databaseName = "dbatoolsci_azmigration_$suffix"
        $testPath = "/tmp/$databaseName"
        $destinationConnectionString = "Server=dbatoolstestmigration.database.windows.net;Authentication=Active Directory Service Principal;Database=master;User Id=$env:CLIENTID;Password=$env:CLIENTSECRET;Encrypt=True;TrustServerCertificate=False;"
        $sourceServer = $null
        $verificationServer = $null
        $retainedBacpacPath = $null
        $primaryError = $null
        $cleanupErrors = @()

        try {
            $null = New-Item -Path $testPath -ItemType Directory -Force
            $sourceServer = Connect-DbaInstance -SqlInstance "localhost" -SqlCredential $sourceCredential -Database "master"
            $null = New-DbaDatabase -SqlInstance $sourceServer -Name $databaseName -EnableException
            $sourceQuery = @"
CREATE TABLE dbo.MigrationProof
(
    Id int NOT NULL PRIMARY KEY,
    Value int NOT NULL
);
INSERT dbo.MigrationProof (Id, Value)
VALUES (1, 10), (2, 20), (3, 30);
"@
            $null = Invoke-DbaQuery -SqlInstance $sourceServer -Database $databaseName -Query $sourceQuery -EnableException

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

            $initialResult = Start-DbaAzMigration @migrationSplat
            $initialResult.Status | Should -Be "Successful"
            $initialResult.Type | Should -Be "Database"
            $initialResult.Name | Should -Be $databaseName
            $initialResult.DestinationDatabase | Should -Be $databaseName
            $initialResult.PSObject.Properties.Name | Should -Contain "SourceServer"
            $initialResult.PSObject.Properties.Name | Should -Contain "DestinationServer"
            $initialResult.PSObject.Properties.Name | Should -Contain "Notes"
            $initialResult.PSObject.Properties.Name | Should -Contain "DateTime"
            $initialResult.PSObject.Properties.Name | Should -Contain "BacpacPath"
            $initialResult.PSObject.Properties.Name | Should -Contain "Elapsed"
            Test-Path -LiteralPath $initialResult.BacpacPath | Should -BeFalse

            $verificationConnectionString = $destinationConnectionString.Replace("Database=master", "Database=$databaseName")
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $rows = Invoke-DbaQuery -SqlInstance $verificationServer -Database $databaseName -Query "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id" -EnableException
            ($rows.Id -join ",") | Should -Be "1,2,3"
            ($rows.Value -join ",") | Should -Be "10,20,30"

            $null = Invoke-DbaQuery -SqlInstance $verificationServer -Database $databaseName -Query "UPDATE dbo.MigrationProof SET Value = 999 WHERE Id = 1" -EnableException
            $skippedResult = Start-DbaAzMigration @migrationSplat
            $skippedResult.Status | Should -Be "Skipped"
            $skippedResult.Notes | Should -Be "Already exists on destination"
            $unchangedValue = Invoke-DbaQuery -SqlInstance $verificationServer -Database $databaseName -Query "SELECT Value FROM dbo.MigrationProof WHERE Id = 1" -EnableException
            $unchangedValue.Value | Should -Be 999

            $null = Disconnect-DbaInstance -InputObject $verificationServer
            $verificationServer = $null
            $forcedResult = Start-DbaAzMigration @migrationSplat -Force
            $forcedResult.Status | Should -Be "Successful"
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $forcedRows = Invoke-DbaQuery -SqlInstance $verificationServer -Database $databaseName -Query "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id" -EnableException
            ($forcedRows.Id -join ",") | Should -Be "1,2,3"
            ($forcedRows.Value -join ",") | Should -Be "10,20,30"

            $null = Disconnect-DbaInstance -InputObject $verificationServer
            $verificationServer = $null
            $retainedResult = Start-DbaAzMigration @migrationSplat -Force -KeepBacpac
            $retainedResult.Status | Should -Be "Successful"
            $retainedBacpacPath = $retainedResult.BacpacPath
            Test-Path -LiteralPath $retainedBacpacPath | Should -BeTrue
            $verificationServer = Connect-DbaInstance -SqlInstance $verificationConnectionString
            $retainedRows = Invoke-DbaQuery -SqlInstance $verificationServer -Database $databaseName -Query "SELECT Id, Value FROM dbo.MigrationProof ORDER BY Id" -EnableException
            ($retainedRows.Value -join ",") | Should -Be "10,20,30"
        } catch {
            $primaryError = $PSItem
        } finally {
            if ($verificationServer) {
                try {
                    $null = Disconnect-DbaInstance -InputObject $verificationServer
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            try {
                $destinationMaster = Connect-DbaInstance -SqlInstance $destinationConnectionString
                $destinationDatabase = Get-DbaDatabase -SqlInstance $destinationMaster -Database $databaseName
                if ($destinationDatabase) {
                    $null = Remove-DbaDatabase -InputObject $destinationDatabase -Confirm:$false -EnableException
                    $destinationMaster.Databases.Refresh()
                    $remainingDatabase = Get-DbaDatabase -SqlInstance $destinationMaster -Database $databaseName
                    if ($remainingDatabase) {
                        throw "Azure cleanup did not drop $databaseName."
                    }
                }
                $null = Disconnect-DbaInstance -InputObject $destinationMaster
            } catch {
                $cleanupErrors += $PSItem
            }

            if ($sourceServer) {
                try {
                    $sourceDatabase = Get-DbaDatabase -SqlInstance $sourceServer -Database $databaseName
                    if ($sourceDatabase) {
                        $null = Remove-DbaDatabase -SqlInstance $sourceServer -Database $databaseName -Confirm:$false -EnableException
                    }
                    $null = Disconnect-DbaInstance -InputObject $sourceServer
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if ($retainedBacpacPath -and (Test-Path -LiteralPath $retainedBacpacPath)) {
                try {
                    Remove-Item -LiteralPath $retainedBacpacPath -Force -ErrorAction Stop
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

            if (Test-Path -LiteralPath $testPath) {
                try {
                    Remove-Item -LiteralPath $testPath -Recurse -Force -ErrorAction Stop
                } catch {
                    $cleanupErrors += $PSItem
                }
            }

        }

        if ($primaryError) {
            throw $primaryError
        }
        if ($cleanupErrors.Count -gt 0) {
            throw "Start-DbaAzMigration integration cleanup failed: $($cleanupErrors.Exception.Message -join '; ')"
        }
    }
}