#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbVirtualLogFile",
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
                "IncludeSystemDBs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Get-DbaNoun
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testDbName = "dbatoolsci_getvlf"
        $splatDatabase = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Name            = $testDbName
            EnableException = $true
        }
        $null = New-DbaDatabase @splatDatabase

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $splatVirtualLogFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDbName
            }
            $allResults = Get-DbaDbVirtualLogFile @splatVirtualLogFile
        }

        It "Should have correct properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "RecoveryUnitId",
                "FileId",
                "FileSize",
                "StartOffset",
                "FSeqNo",
                "Status",
                "Parity",
                "CreateLSN"
            )
            ($allResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProperties | Sort-Object)
        }

        It "Should have database name of $testDbName" {
            foreach ($result in $allResults) {
                $result.Database | Should -Be $testDbName
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputValidation = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $testDbName
                IncludeSystemDBs = $false
            }
            $outputResult = Get-DbaDbVirtualLogFile @splatOutputValidation
        }

        It "Returns output of the documented type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "RecoveryUnitId",
                "FileId",
                "FileSize",
                "StartOffset",
                "FSeqNo",
                "Status",
                "Parity",
                "CreateLsn"
            )
            foreach ($prop in $expectedProperties) {
                $outputResult[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}