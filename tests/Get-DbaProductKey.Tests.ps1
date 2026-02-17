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
            $results = Get-DbaProductKey -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Version",
                "Edition",
                "Key"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}