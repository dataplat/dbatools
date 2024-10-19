param($ModuleName = 'dbatools')

Describe "Get-DbaAgentLog" {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentLog
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "LogNumber",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command gets agent log" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $global:instance2
        }
        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Results contain SQLServerAgent version" {
            $results.text -like '[100] Microsoft SQLServerAgent version*' | Should -Be $true
        }
        It "LogDate is a DateTime type" {
            $results[0].LogDate | Should -BeOfType DateTime
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $global:instance2 -LogNumber 0
        }
        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
