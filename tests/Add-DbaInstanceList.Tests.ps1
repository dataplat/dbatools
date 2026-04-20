#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaInstanceList",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Register",
                "Scope"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instanceName = "dbatoolsci_testinstance_$(Get-Random)"
    }

    AfterAll {
        $null = Remove-DbaInstanceList -SqlInstance $instanceName -ErrorAction SilentlyContinue
    }

    Context "adds instances to the list" {
        It "adds an instance without error" {
            { Add-DbaInstanceList -SqlInstance $instanceName } | Should -Not -Throw
        }

        It "instance appears in Get-DbaInstanceList after adding" {
            $result = Get-DbaInstanceList
            $result | Should -Contain $instanceName.ToLowerInvariant()
        }

        It "instance appears in the TEPP cache after adding" {
            $cache = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"]
            $cache | Should -Contain $instanceName.ToLowerInvariant()
        }

        It "does not add duplicates" {
            Add-DbaInstanceList -SqlInstance $instanceName
            $result = Get-DbaInstanceList
            ($result | Where-Object { $PSItem -eq $instanceName.ToLowerInvariant() }).Count | Should -Be 1
        }
    }
}
