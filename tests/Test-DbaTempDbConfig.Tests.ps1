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
            $results = Test-DbaTempDbConfig -SqlInstance $server -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Rule",
                "Recommended",
                "CurrentSetting",
                "IsBestPractice",
                "Notes"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should return 6 rule results per instance" {
            $global:dbatoolsciOutput.Count | Should -Be 6
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}