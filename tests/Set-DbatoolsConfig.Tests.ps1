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
        It "impacts the connection timeout" {
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60 -PassThru -OutVariable "global:dbatoolsciOutput"
            $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
            $results | Should -Match "Connect Timeout=60"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Configuration.Config]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Description",
                "FullName",
                "Handler",
                "Hidden",
                "Initialized",
                "Module",
                "ModuleExport",
                "Name",
                "PolicyEnforced",
                "PolicySet",
                "RegistryData",
                "SafeValue",
                "SimpleExport",
                "Type",
                "Unchanged",
                "Validation",
                "Value"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }
    }
}