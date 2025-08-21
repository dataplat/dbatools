#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbGrowthEvent",
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
                "ExcludeDatabase",
                "EventType",
                "FileType",
                "UseLocalTime",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1

            $sqlGrowthAndShrink = @"
CREATE TABLE Tab1 (ID INTEGER);

INSERT INTO Tab1 (ID)
SELECT
    1
FROM
    sys.all_objects a
CROSS JOIN
    sys.all_objects b;

TRUNCATE TABLE Tab1;
DBCC SHRINKFILE ($databaseName1, TRUNCATEONLY);
DBCC SHRINKFILE ($($databaseName1)_Log, TRUNCATEONLY);
"@

            $null = $db1.Query($sqlGrowthAndShrink)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $db1 | Remove-DbaDatabase -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find auto growth events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Growth
            @($results | Where-Object EventClass -in 92, 93).Count | Should -BeGreaterThan 0
            $results.DatabaseName | Select-Object -Unique | Should -Be $databaseName1
            $results.DatabaseId | Select-Object -Unique | Should -Be $db1.ID
        }

        <# Leaving this commented out since the background process for auto shrink cannot be triggered

        It "Should find auto shrink events in the default trace" {
            $results = Find-DbaDbGrowthEvent -SqlInstance $server -Database $databaseName1 -EventType Shrink
            $results.EventClass | Should -Contain 94 # data file shrink
            $results.EventClass | Should -Contain 95 # log file shrink
            $results.DatabaseName | Select-Object -Unique | Should -Be $databaseName1
            $results.DatabaseId | Select-Object -Unique | Should -Be $db1.ID
        }
        #>
    }
}