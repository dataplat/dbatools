#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFilestream",
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
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Getting FileStream Level" {
        It "Should have changed the FileStream Level" {
            $results = Get-DbaFilestream -SqlInstance $TestConfig.InstanceSingle
            $results.InstanceAccess | Should -BeIn "Disabled", "T-SQL access enabled", "Full access enabled"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaFilestream -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'InstanceAccess',
                'ServiceAccess',
                'ServiceShareName'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties accessible via Select-Object" {
            $additionalProps = @(
                'InstanceAccessLevel',
                'ServiceAccessLevel',
                'Credential',
                'SqlCredential'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }

        It "InstanceAccess contains a valid value" {
            $result.InstanceAccess | Should -BeIn "Disabled", "T-SQL access enabled", "Full access enabled"
        }

        It "ServiceAccess contains a valid value" {
            $result.ServiceAccess | Should -BeIn "Disabled", "FileStream enabled for T-Sql access", "FileStream enabled for T-Sql and IO streaming access", "FileStream enabled for T-Sql, IO streaming, and remote clients"
        }
    }
}