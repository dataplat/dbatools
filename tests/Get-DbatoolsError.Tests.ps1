#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "First",
                "Last",
                "Skip",
                "All"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets an error" {
        It "returns a dbatools error" {
            try {
                $null = Connect-DbaInstance -SqlInstance "nothing" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            Get-DbatoolsError | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Generate a dbatools error for testing
            try {
                $null = Connect-DbaInstance -SqlInstance "invalidserver123" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            $result = Get-DbatoolsError -First 1
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'CategoryInfo',
                'ErrorDetails',
                'Exception',
                'FullyQualifiedErrorId',
                'InvocationInfo',
                'PipelineIterationInfo',
                'PSMessageDetails',
                'ScriptStackTrace',
                'TargetObject'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Filters to only dbatools errors" {
            $result.FullyQualifiedErrorId | Should -Match 'dbatools'
        }
    }

    Context "Output with -All parameter" {
        BeforeAll {
            # Generate multiple dbatools errors
            try {
                $null = Connect-DbaInstance -SqlInstance "invalidserver1" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            try {
                $null = Connect-DbaInstance -SqlInstance "invalidserver2" -ConnectTimeout 1 -ErrorAction Stop
            } catch { }
            $result = Get-DbatoolsError -All
        }

        It "Returns multiple ErrorRecord objects when -All specified" {
            $result.Count | Should -BeGreaterThan 0
            foreach ($item in $result) {
                $item | Should -BeOfType [System.Management.Automation.ErrorRecord]
            }
        }
    }
}