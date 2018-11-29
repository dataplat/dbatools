$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Stop-DbaXESession).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'AllSessions', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $conn = $server.ConnectionContext
        # Get the systemhealth session
        $systemhealth = Get-DbaXESession -SqlInstance $server -Session system_health
        # Create a valid session and start it
        $conn.ExecuteNonQuery("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
        $dbatoolsciValid = Get-DbaXESession -SqlInstance $server -Session dbatoolsci_session_valid
        $dbatoolsciValid.Start()
        # Record the Status of all sessions
        $allSessions = Get-DbaXESession -SqlInstance $server
    }
    BeforeEach {
        $systemhealth.Refresh()
        if (-Not $systemhealth.IsRunning) {
            $systemhealth.Start()
        }
    }
    AfterAll {
        # Set the Status of all session back to what they were before the test
        foreach ($session in $allSessions) {
            $session.Refresh()
            if ($session.Status -eq "Stopped") {
                if ($session.IsRunning) {
                    $session.Stop()
                }
            } else {
                if (-Not $session.IsRunning) {
                    $session.Start()
                }
            }
        }

        # Drop created objects
        $conn.ExecuteNonQuery("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
    }

    Context "Verifying command works" {
        It "stops the system_health session" {
            $systemhealth | Stop-DbaXESession
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should Be $false
        }

        It "does not change state if XE session is already stopped" {
            if ($systemhealth.IsRunning) {
                $systemhealth.Stop()
            }
            Stop-DbaXESession $server -Session $systemhealth.Name -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should Be $false
        }

        It "stops all XE Sessions except the system ones if -AllSessions is used" {
            Stop-DbaXESession $server -AllSessions -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $dbatoolsciValid.Refresh()
            $systemhealth.IsRunning | Should Be $true
            $dbatoolsciValid.IsRunning | Should Be $false
        }
    }
}