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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
