#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileMapping",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "returns information about multiple databases" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $true
        }
    }

    Context "Should return file information for a single database" {
        BeforeAll {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        }

        It "returns information about tempdb" {
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $false
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "FileMapping")
            foreach ($prop in $expectedProps) {
                $results[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has a FileMapping property that is a hashtable" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].FileMapping | Should -BeOfType [hashtable]
            $results[0].FileMapping.Count | Should -BeGreaterThan 0
        }
    }
}