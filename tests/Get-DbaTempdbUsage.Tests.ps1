#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTempdbUsage",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving tempdb usage" {
        It "Executes the tempdb usage query without error" {
            # The DMV join only reports sessions with an ACTIVE request allocating
            # tempdb, so an idle lab legitimately returns zero rows - the honest
            # characterization here is the no-throw contract on a live instance.
            { $null = Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Not -Throw
        }
    }
}