#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Module",
                "Name",
                "Value",
                "PersistedValue",
                "PersistedType",
                "Description",
                "Validation",
                "Handler",
                "Hidden",
                "Default",
                "Initialize",
                "SimpleExport",
                "ModuleExport",
                "DisableValidation",
                "DisableHandler",
                "PassThru",
                "Register",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When setting configuration values" {
        BeforeAll {
            $result = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60 -PassThru
            $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
        }

        It "impacts the connection timeout" {
            $results | Should -Match "Connect Timeout=60"
        }

        It "Returns no output without -PassThru" {
            $noOutput = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 30
            $noOutput | Should -BeNullOrEmpty
        }

        It "Returns output of the expected type with -PassThru" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Configuration.Config"
        }

        It "Has the expected properties on the config object" {
            $result.FullName | Should -Not -BeNullOrEmpty
            $result.Value | Should -Not -BeNullOrEmpty
            $result.Module | Should -Not -BeNullOrEmpty
            $result.Name | Should -Not -BeNullOrEmpty
        }
    }
}