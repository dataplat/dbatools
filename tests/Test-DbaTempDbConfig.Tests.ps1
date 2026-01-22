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
    Context "Output Validation" {
        BeforeAll {
            $results = Test-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $results[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Returns exactly 6 objects (one per tempdb rule)" {
            $results.Count | Should -Be 6
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Rule',
                'Recommended',
                'CurrentSetting',
                'IsBestPractice',
                'Notes'
            )
            $actualProps = $results[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns all expected rule names" {
            $expectedRules = @(
                'TF 1118 Enabled',
                'File Count',
                'File Growth in Percent',
                'File Location',
                'File MaxSize Set',
                'Data File Size Equal'
            )
            $actualRules = $results.Rule
            foreach ($rule in $expectedRules) {
                $actualRules | Should -Contain $rule -Because "rule '$rule' should be evaluated"
            }
        }
    }

    Context "Command actually works on $($TestConfig.InstanceSingle)" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $results = Test-DbaTempDbConfig -SqlInstance $server
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