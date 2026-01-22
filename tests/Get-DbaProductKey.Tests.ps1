#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:AppVeyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    Context "Gets ProductKey for Instances on $(([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName)" {
        BeforeAll {
            $results = Get-DbaProductKey -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Version for each result" {
            foreach ($row in $results) {
                $row.Version | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Edition for each result" {
            foreach ($row in $results) {
                $row.Edition | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Key for each result" {
            foreach ($row in $results) {
                $row.Key | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaProductKey -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Version',
                'Edition',
                'Key'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}