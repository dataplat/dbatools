#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaWhoIsActive",
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
                "LocalFile",
                "Database",
                "EnableException",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "WhoIsActive-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should install sp_WhoIsActive" {
        It "Should output correct results" {
            $installResults = Install-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $installResults.Database | Should -Be $dbName
            $installResults.Name | Should -Be "sp_WhoisActive"
            $installResults.Status | Should -Be "Installed"
        }
    }

    Context "Should update sp_WhoIsActive" {
        It "Should output correct results" {
            $updateResults = Install-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $updateResults.Database | Should -Be $dbName
            $updateResults.Name | Should -Be "sp_WhoisActive"
            $updateResults.Status | Should -Be "Updated"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDbName = "dbatoolsci_whoisactive_output_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName
            $result = Install-DbaWhoIsActive -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Version", "Status")
            foreach ($prop in $expectedProps) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has correct values for standard properties" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $outputDbName
            $result.Name | Should -Be "sp_WhoisActive"
            $result.Status | Should -Be "Installed"
        }
    }
}