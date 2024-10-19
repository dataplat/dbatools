param($ModuleName = 'dbatools')

Describe "Remove-DbaDbMirrorMonitor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbMirrorMonitor
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database msdb
            if (($db.Tables['dbm_monitor_data'].Name)) {
                $env:putback = $true
            } else {
                $null = Add-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
            }
        }

        AfterAll {
            if ($env:putback) {
                # add it back
                $results = Add-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
            }
        }

        It "removes the mirror monitor" {
            $results = Remove-DbaDbMirrorMonitor -SqlInstance $global:instance2 -WarningAction SilentlyContinue
            $results.MonitorStatus | Should -Be 'Removed'
        }
    }
}
