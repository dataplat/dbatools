#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaMaintenanceSolution",
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
                "Solution",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Install the maintenance solution in tempdb so we can update it
        $cleanupQuery = "
            IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
            IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
            IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
            IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
            IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
            IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
            IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
        "
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $cleanupQuery

        $splatInstall = @{
            SqlInstance     = $TestConfig.InstanceMulti1
            Database        = "tempdb"
            ReplaceExisting = $true
        }
        $null = Install-DbaMaintenanceSolution @splatInstall

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupQuery = "
            IF OBJECT_ID('dbo.CommandExecute', 'P') IS NOT NULL DROP PROCEDURE dbo.CommandExecute;
            IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseBackup;
            IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL DROP PROCEDURE dbo.DatabaseIntegrityCheck;
            IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL DROP PROCEDURE dbo.IndexOptimize;
            IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL DROP TABLE dbo.CommandLog;
            IF OBJECT_ID('dbo.Queue', 'U') IS NOT NULL DROP TABLE dbo.Queue;
            IF OBJECT_ID('dbo.QueueDatabase', 'U') IS NOT NULL DROP TABLE dbo.QueueDatabase;
        "
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $cleanupQuery

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When updating maintenance solution" {
        BeforeAll {
            $splatUpdate = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = "tempdb"
            }
            $global:dbatoolsciOutput = Update-DbaMaintenanceSolution @splatUpdate
        }

        It "Should return results for all solution components" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
            $global:dbatoolsciOutput.Count | Should -BeGreaterOrEqual 4
        }

        It "Should show updated status for installed procedures" {
            $updated = $global:dbatoolsciOutput | Where-Object IsUpdated -eq $true
            $updated | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Solution",
                "Procedure",
                "IsUpdated",
                "Results"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}