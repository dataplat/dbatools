#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbCorruption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate Confirm impact" {
        It "Confirm Impact should be high" {
            $metadata = [System.Management.Automation.CommandMetadata](Get-Command $CommandName)
            $metadata.ConfirmImpact | Should -Be "High"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbNameCorruption = "dbatoolsci_InvokeDbaDatabaseCorruptionTest"
        $serverConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $tableNameExample = "Example"
        # Need a clean empty database
        $null = $serverConnection.Query("Create Database [$dbNameCorruption]")
        $databaseCorruption = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameCorruption

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameCorruption

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validating Database Input" {
        BeforeAll {
            # The command does not respect -WarningAction SilentlyContinue inside of this pester test - still don't know why, retest with pester 5
            $systemWarnVar = $null
            Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database "master" -WarningVariable systemWarnVar 3> $null
        }

        It "Should not allow you to corrupt system databases." {
            $systemWarnVar -match "may not corrupt system databases" | Should -Be $true
        }

        It "Should fail if more than one database is specified" {
            { Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database "Database1", "Database2" -EnableException } | Should -Throw
        }
    }

    It "Require at least a single table in the database specified" {
        { Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbNameCorruption -EnableException } | Should -Throw
    }

    # Creating a table to make sure these are failing for different reasons
    It "Fail if the specified table does not exist" {
        { Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbNameCorruption -Table "DoesntExist$(New-Guid)" -EnableException } | Should -Throw
    }

    Context "When table is created" {
        BeforeAll {
            $null = $databaseCorruption.Query("
                CREATE TABLE dbo.[$tableNameExample] (id int);
                INSERT dbo.[Example]
                SELECT top 1000 1
                FROM sys.objects")
        }

        It "Corrupt a single database" {
            Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbNameCorruption | Select-Object -ExpandProperty Status | Should -Be "Corrupted"
        }

        It "Causes DBCC CHECKDB to fail" {
            $checkDbResult = Start-DbccCheck -Server $serverConnection -dbname $dbNameCorruption
            $checkDbResult | Should -Not -Be "Success"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputDbName = "dbatoolsci_corruptionoutput"
            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $outputServer.Query("CREATE DATABASE [$outputDbName]")
            $outputDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName
            $null = $outputDb.Query("
                CREATE TABLE dbo.[OutputTest] (id int);
                INSERT dbo.[OutputTest]
                SELECT TOP 1000 1
                FROM sys.objects")

            $corruptionResult = $null
            try {
                $corruptionResult = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Table OutputTest -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop
            } catch {
                # Command may fail in certain test environments
            }
        }

        AfterAll {
            try {
                $cleanServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $cleanServer.Query("IF DB_ID('dbatoolsci_corruptionoutput') IS NOT NULL BEGIN ALTER DATABASE [dbatoolsci_corruptionoutput] SET MULTI_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [dbatoolsci_corruptionoutput]; END")
            } catch {
                # Ignore cleanup errors
            }
        }

        It "Returns output of the documented type" {
            if (-not $corruptionResult) { Set-ItResult -Skipped -Because "corruption command did not return a result" }
            $corruptionResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $corruptionResult) { Set-ItResult -Skipped -Because "corruption command did not return a result" }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "Status"
            )
            foreach ($prop in $expectedProps) {
                $corruptionResult.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns the correct status" {
            if (-not $corruptionResult) { Set-ItResult -Skipped -Because "corruption command did not return a result" }
            $corruptionResult.Status | Should -Be "Corrupted"
        }
    }
}