#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcSharedVolume",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $results = Get-DbaWsfcSharedVolume -ComputerName $TestConfig.InstanceHadr -WarningVariable WarnVar -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate output" {
        It "Should return shared volume information without errors" {
            $WarnVar | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Management.ManagementObject]
        }

        It "Should have the added ClusterName property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "ClusterName"
        }

        It "Should have the added ClusterFqdn property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "ClusterFqdn"
        }

        It "Should have the added State property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "State"
        }

        It "Should have a non-empty ClusterName property" {
            if (-not $global:dbatoolsciOutput) { Set-ItResult -Skipped -Because "no output to validate" }
            $global:dbatoolsciOutput[0].ClusterName | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "ManagementObject"
        }
    }
}