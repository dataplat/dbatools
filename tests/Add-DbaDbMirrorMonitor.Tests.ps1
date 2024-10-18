param($ModuleName = 'dbatools')

Describe "Add-DbaDbMirrorMonitor" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaDbMirrorMonitor
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
        }
        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
        }

        It "adds the mirror monitor" {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
            $results.MonitorStatus | Should -Be 'Added'
        }
    }
}
