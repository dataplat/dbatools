param($ModuleName = 'dbatools')

Describe "Test-DbaBuild" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaBuild
        }
        It "Should have Build parameter" {
            $CommandUnderTest | Should -HaveParameter Build -Type Version[] -Mandatory:$false
        }
        It "Should have MinimumBuild parameter" {
            $CommandUnderTest | Should -HaveParameter MinimumBuild -Type Version -Mandatory:$false
        }
        It "Should have MaxBehind parameter" {
            $CommandUnderTest | Should -HaveParameter MaxBehind -Type String -Mandatory:$false
        }
        It "Should have Latest parameter" {
            $CommandUnderTest | Should -HaveParameter Latest -Type Switch -Mandatory:$false
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Update parameter" {
            $CommandUnderTest | Should -HaveParameter Update -Type Switch -Mandatory:$false
        }
        It "Should have Quiet parameter" {
            $CommandUnderTest | Should -HaveParameter Quiet -Type Switch -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Retired KBs" {
        It "Handles retired kbs" {
            $result = Test-DbaBuild -Build '13.0.5479' -Latest
            $result.Warning | Should -Be 'This version has been officially retired by Microsoft'
            $latestCUfor2019 = (Test-DbaBuild -Build '15.0.4003' -MaxBehind '0CU').CUTarget.Replace('CU', '')
            #CU7 for 2019 was retired
            $behindforCU7 = [int]$latestCUfor2019 - 7
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

    Context "Command actually works" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        It "Should return a result" {
            $results = Test-DbaBuild -Build "12.00.4502" -MinimumBuild "12.0.4511" -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result" {
            $results = Test-DbaBuild -Build "12.0.5540" -MaxBehind "1SP 1CU" -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
