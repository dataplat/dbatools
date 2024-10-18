param($ModuleName = 'dbatools')

Describe "Get-DbaAgentLog" {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentLog
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have LogNumber as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogNumber -Type System.Int32[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
