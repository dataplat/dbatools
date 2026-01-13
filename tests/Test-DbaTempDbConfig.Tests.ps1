#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaTempDbConfig",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works on $($TestConfig.InstanceSingle)" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $results = Test-DbaTempDbConfig -SqlInstance $server
        }

        It "Should have correct properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Rule",
                "Recommended",
                "CurrentSetting",
                "IsBestPractice",
                "Notes"
            )
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedProps | Sort-Object)
        }

        It "Should return correct value for IsBestPractice with rule: File Location" {
            $rule = "File Location"
            if ($server.Databases["tempdb"].FileGroups[0].Files[0].FileName.Substring(0, 1) -eq "C") {
                $isBestPractice = $false
            } else {
                $isBestPractice = $true
            }
            ($results | Where-Object Rule -match $rule).IsBestPractice | Should -BeExactly $isBestPractice
        }

        It "Should return false for Recommended with rule: File Location" {
            $rule = "File Location"
            ($results | Where-Object Rule -match $rule).Recommended | Should -BeExactly $false
        }

        It "Should return correct value for Recommended with rule: TF 1118 Enabled" {
            $rule = "TF 1118 Enabled"
            if ($server.VersionMajor -ge 13) {
                $recommended = $false
            } else {
                $recommended = $true
            }
            ($results | Where-Object Rule -match $rule).Recommended | Should -BeExactly $recommended
        }
    }
}