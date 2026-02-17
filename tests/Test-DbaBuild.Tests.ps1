#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaBuild",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Build",
                "MinimumBuild",
                "MaxBehind",
                "Latest",
                "SqlInstance",
                "SqlCredential",
                "Update",
                "Quiet",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Retired KBs" {
        It "Handles retired kbs" {
            $result = Test-DbaBuild -Build '13.0.5479' -Latest
            $result.Warning | Should -Be 'This version has been officially retired by Microsoft'
            $latestCUfor2019 = (Test-DbaBuild -Build '15.0.4003' -MaxBehind '0CU').CUTarget.Replace('CU', '')
            #CU7 for 2019 was retired
            [int]$behindforCU7 = [int]$latestCUfor2019 - 7
            $goBackTo = "$($behindforCU7)CU"
            $result = Test-DbaBuild -Build '15.0.4003' -MaxBehind $goBackTo
            $result.CUTarget | Should -Be 'CU6'
        }
    }

    Context "Recognizes version 'aliases', see #8915" {
        It 'works with versions with the minor being either not 0 or 50' {
            $result2016 = Test-DbaBuild -Build '13.3.6300' -Latest
            $result2016.Build | Should -Be '13.3.6300'
            $result2016.BuildLevel | Should -Be '13.0.6300'
            $result2016.MatchType | Should -Be 'Exact'

            $result2008R2 = Test-DbaBuild -Build '10.53.6220'  -Latest
            $result2008R2.Build | Should -Be '10.53.6220'
            $result2008R2.BuildLevel | Should -Be '10.50.6220'
            $result2008R2.MatchType | Should -Be 'Exact'
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaBuild -Build "12.00.4502" -MinimumBuild "12.0.4511" -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -Be $null
        }

        It "Should return a result" {
            $results = Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP 1CU" -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
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
                "SqlInstance",
                "Build",
                "NameLevel",
                "SPLevel",
                "CULevel",
                "KBLevel",
                "BuildLevel",
                "SupportedUntil",
                "MatchType",
                "Warning",
                "Compliant",
                "MinimumBuild",
                "MaxBehind",
                "SPTarget",
                "CUTarget",
                "BuildTarget"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "Build",
                "BuildLevel",
                "Compliant",
                "CULevel",
                "KBLevel",
                "MatchType",
                "MinimumBuild",
                "NameLevel",
                "SPLevel",
                "SqlInstance",
                "SupportedUntil",
                "Warning"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}