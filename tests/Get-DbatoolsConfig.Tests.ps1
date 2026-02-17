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
                "Force"
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

        It "Should have the expected properties" {
            $expectedProperties = @(
                "FullName",
                "Type",
                "Value",
                "SafeValue",
                "Unchanged",
                "Initialized",
                "PolicyEnforced",
                "RegistryData",
                "Name",
                "Module",
                "Description",
                "Handler",
                "Validation",
                "Hidden",
                "PolicySet",
                "SimpleExport",
                "ModuleExport"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Configuration\.Config"
        }
    }
}