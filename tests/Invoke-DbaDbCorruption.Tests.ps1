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

    Context "Output Validation" {
        BeforeAll {
            # Recreate clean database for output validation
            $dbNameOutputTest = "dbatoolsci_InvokeDbaDatabaseCorruptionOutput"
            $null = $serverConnection.Query("Create Database [$dbNameOutputTest]")
            $null = $serverConnection.Query("
                USE [$dbNameOutputTest];
                CREATE TABLE dbo.OutputTest (id int);
                INSERT dbo.OutputTest
                SELECT top 100 1
                FROM sys.objects")
            
            $result = Invoke-DbaDbCorruption -SqlInstance $TestConfig.InstanceSingle -Database $dbNameOutputTest -Table "OutputTest" -Confirm:$false -EnableException
        }

        AfterAll {
            # Cleanup output test database
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbNameOutputTest -Confirm:$false
        }

        It "Returns the documented output type" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Table",
                "Status"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Has Status property set to Corrupted" {
            $result.Status | Should -Be "Corrupted"
        }

        It "Has Database property set correctly" {
            $result.Database | Should -Be $dbNameOutputTest
        }

        It "Has Table property set correctly" {
            $result.Table | Should -Be "OutputTest"
        }
    }
}