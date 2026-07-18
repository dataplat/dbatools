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
                "MaxTimeBehind",
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

Describe $CommandName -Tag UnitTests {
    Context "MaxTimeBehind compliance" {
        It "Identifies a build as compliant with a wide time window" {
            # SQL Server 2022 CU10 (16.0.4095) released 2023-11-16 - compliant within 360 months of today (2026-03-30)
            $result = Test-DbaBuild -Build "16.0.4095" -MaxTimeBehind "360Mo"
            $result.Compliant | Should -Be $true
        }

        It "Identifies a build as non-compliant with a narrow time window" {
            # SQL Server 2022 CU10 (16.0.4095) released 2023-11-16 - more than 6 months old as of today (2026-03-30)
            $result = Test-DbaBuild -Build "16.0.4095" -MaxTimeBehind "6Mo"
            $result.Compliant | Should -Be $false
        }

        It "Returns non-compliant when no ReleaseDate is available" {
            # An unrecognized build version has no release date in the index
            $result = Test-DbaBuild -Build "16.0.9999" -MaxTimeBehind "6Mo" -WarningAction SilentlyContinue
            $WarnVar[0] | Should -BeLike "*16.0.9999 is not recognized as a correct version"
            $WarnVar[1] | Should -BeLike "*No ReleaseDate found for build 16.0.9999 - cannot determine time-based compliance"
            $result.Compliant | Should -Be $false
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
            $results = Test-DbaBuild -Build "12.00.4502" -MinimumBuild "12.0.4511" -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }

        It "Should return a result" {
            $results = Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP 1CU" -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }
    }

    Context "Cross-record BuildVersions carry (DEF-008 W1-124)" {
        It "Repeats the first record's builds for a record that binds neither Build nor SqlInstance" {
            # The source's $BuildVersions is branch-assigned but read UNCONDITIONALLY at
            # FUNCTION scope: a piped $null record binds neither -Build nor SqlInstance,
            # so its foreach re-reads the PREVIOUS record's builds and re-emits them
            # (quirk preserved, not a recommendation; probed identical 2026-07-17).
            $carryResults = @(@($TestConfig.InstanceSingle, $null) | Test-DbaBuild -Latest -WarningAction SilentlyContinue)
            $carryResults.Count | Should -BeExactly 2
            $carryResults[1].Build | Should -Be $carryResults[0].Build
            $carryResults[1].SqlInstance | Should -Be $carryResults[0].SqlInstance
        }
    }
}