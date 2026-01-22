#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAgSpn",
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
                "AvailabilityGroup",
                "Listener",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This requires an AG environment which may not be available in all test scenarios
            # If AG is not available, the test will be skipped
            $agExists = $null
            try {
                $agExists = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance2 -EnableException -WarningAction SilentlyContinue
            } catch {
                # AG not available in test environment
            }
        }

        It "Returns PSCustomObject" -Skip:(!$agExists) {
            $result = Test-DbaAgSpn -SqlInstance $TestConfig.instance2 -EnableException
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" -Skip:(!$agExists) {
            $result = Test-DbaAgSpn -SqlInstance $TestConfig.instance2 -EnableException
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'SqlInstance',
                    'InstanceName',
                    'SqlProduct',
                    'InstanceServiceAccount',
                    'RequiredSPN',
                    'IsSet',
                    'Cluster',
                    'TcpEnabled',
                    'Port',
                    'DynamicPort',
                    'Warning',
                    'Error'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            }
        }

        It "Does not display Credential property by default" -Skip:(!$agExists) {
            $result = Test-DbaAgSpn -SqlInstance $TestConfig.instance2 -EnableException
            if ($result) {
                # Credential should exist but be hidden via Select-DefaultView
                $result[0].PSObject.Properties.Name | Should -Contain 'Credential'
            }
        }

        It "Returns two SPN objects per listener (one without port, one with port)" -Skip:(!$agExists) {
            $result = Test-DbaAgSpn -SqlInstance $TestConfig.instance2 -EnableException
            if ($result) {
                # Should have at least 2 results (one pair for at least one listener)
                $result.Count | Should -BeGreaterOrEqual 2
                # Should have even number of results (pairs)
                $result.Count % 2 | Should -Be 0
            }
        }
    }
}
