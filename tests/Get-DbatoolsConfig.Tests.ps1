#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Name",
                "Module",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving configuration values" {
        It "Should return a value that is an int" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout -OutVariable "global:dbatoolsciOutput"
            $results.Value | Should -BeOfType [int]
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Configuration.Config]
        }

        It "Should have a FullName property" {
            $global:dbatoolsciOutput[0].FullName | Should -Not -BeNullOrEmpty
        }

        It "Should have a Module property" {
            $global:dbatoolsciOutput[0].Module | Should -Not -BeNullOrEmpty
        }

        It "Should have a Name property" {
            $global:dbatoolsciOutput[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Should have a Value property" {
            $global:dbatoolsciOutput[0].Value | Should -Not -BeNullOrEmpty
        }

        # NOTE: .OUTPUTS documentation test is deferred until the PS1 wrapper is retired
        # and MAML/XML help is authored for the binary cmdlet. At that point, verify:
        #   (Get-Help $CommandName -Full).returnValues.returnValue.type.name |
        #       Should -Match "Dataplat\.Dbatools\.Configuration\.Config"
    }
}
