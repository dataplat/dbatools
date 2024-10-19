param($ModuleName = 'dbatools')

Describe "Stop-DbaXESession" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaXESession
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "AllSessions",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
            $dbatoolsciValid = Get-DbaXESession -SqlInstance $global:instance2 -Session dbatoolsci_session_valid
            $dbatoolsciValid.Start()
            $allSessions = Get-DbaXESession -SqlInstance $global:instance2
        }

        BeforeEach {
            $dbatoolsciValid.Refresh()
            if (-Not $dbatoolsciValid.IsRunning) {
                $dbatoolsciValid.Start()
            }
        }

        AfterAll {
            foreach ($session in $allSessions) {
                $session.Refresh()
                if ($session.Status -eq "Stopped") {
                    if ($session.IsRunning) {
                        $session | Stop-DbaXESession
                    }
                } else {
                    if (-Not $session.IsRunning) {
                        $session | Start-DbaXESession
                    }
                }
            }

            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
        }

        It "stops the dbatoolsci_session_valid session" {
            $dbatoolsciValid | Stop-DbaXESession
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }

        It "does not change state if XE session is already stopped" {
            if ($dbatoolsciValid.IsRunning) {
                $dbatoolsciValid.Stop()
            }
            Stop-DbaXESession -SqlInstance $server -Session $dbatoolsciValid.Name -WarningAction SilentlyContinue
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }

        It "stops all XE Sessions except the system ones if -AllSessions is used" {
            Stop-DbaXESession $server -AllSessions -WarningAction SilentlyContinue
            $dbatoolsciValid.Refresh()
            $dbatoolsciValid.IsRunning | Should -Be $false
        }
    }
}
