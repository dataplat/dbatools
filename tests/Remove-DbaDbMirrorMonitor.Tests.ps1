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
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database msdb
            if (($db.Tables['dbm_monitor_data'].Name)) {
                $script:putback = $true
            } else {
                $null = Add-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
            }
        }

        AfterAll {
            if ($script:putback) {
                # add it back
                $results = Add-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
            }
        }

        It "removes the mirror monitor" {
            $results = Remove-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
            $results.MonitorStatus | Should -Be 'Removed'
        }
    }
}
