param($ModuleName = 'dbatools')

Describe "Remove-DbaDbMirrorMonitor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbMirrorMonitor
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $env:instance2 -Database msdb
            if (($db.Tables['dbm_monitor_data'].Name)) {
                $env:putback = $true
            } else {
                $null = Add-DbaDbMirrorMonitor -SqlInstance $env:instance2 -WarningAction SilentlyContinue
            }
        }

        AfterAll {
            if ($env:putback) {
                # add it back
                $results = Add-DbaDbMirrorMonitor -SqlInstance $env:instance2 -WarningAction SilentlyContinue
            }
        }

        It "removes the mirror monitor" {
            $results = Remove-DbaDbMirrorMonitor -SqlInstance $env:instance2 -WarningAction SilentlyContinue
            $results.MonitorStatus | Should -Be 'Removed'
        }
    }
}
