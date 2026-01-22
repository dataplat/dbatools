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
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60
            $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
            $results | Should -Match "Connect Timeout=60"
        }
    }

    Context "Output without -PassThru" {
        It "Returns no output by default" {
            $result = Set-DbatoolsConfig -FullName "dbatools.test.outputvalidation" -Value "NoPassThru"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation with -PassThru" {
        BeforeAll {
            $result = Set-DbatoolsConfig -FullName "dbatools.test.outputvalidation" -Value "TestValue" -PassThru -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Configuration.Config]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'FullName',
                'Module',
                'Name',
                'Value',
                'Description'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the full set of Config object properties" {
            $expectedProps = @(
                'Description',
                'FullName',
                'Handler',
                'Hidden',
                'Initialized',
                'Module',
                'ModuleExport',
                'Name',
                'PolicyEnforced',
                'PolicySet',
                'RegistryData',
                'SafeValue',
                'SimpleExport',
                'Type',
                'Unchanged',
                'Validation',
                'Value'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }

        It "Returns a configuration object with the set value" {
            $result.Value | Should -Be "TestValue"
            $result.FullName | Should -Be "dbatools.test.outputvalidation"
        }
    }
}