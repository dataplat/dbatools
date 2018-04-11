$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $conn = $server.ConnectionContext
        # Get the systemhealth session
        $systemhealth = Get-DbaXESession -SqlInstance $server -Session system_health
        # Create a session with an invalid target
        $conn.ExecuteNonQuery("CREATE EVENT SESSION [dbatoolsci_session_invalid] ON SERVER ADD EVENT sqlserver.lock_acquired ADD TARGET package0.etw_classic_sync_target (SET default_etw_session_logfile_path = N'C:\dbatoolsci_session_doesnotexist\logfile.etl' );")
        $dbatoolsciInvalid = Get-DbaXESession -SqlInstance $server -Session dbatoolsci_session_invalid
        # Create a valid session
        $conn.ExecuteNonQuery("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
        $dbatoolsciValid = Get-DbaXESession -SqlInstance $server -Session dbatoolsci_session_valid
        # Record the Status of all sessions
        $allSessions = Get-DbaXESession -SqlInstance $server
    }
    BeforeEach {
        <#
        $systemhealth.Refresh()
        if ($systemhealth.IsRunning) {
            $systemhealth.Stop()
        }
        #>
        $systemhealth | Stop-DbaXESession #-ErrorAction SilentlyContinue
    }
    AfterAll {
        # Set the Status of all session back to what they were before the test
        foreach ($session in $allSessions) {
            $session.Refresh()
            if ($session.Status -eq "Stopped") {
                if ($session.IsRunning) {
                    $session.Stop()
                }
            }
            else {
                if (-Not $session.IsRunning) {
                    $session.Start()
                }
            }
        }

        # Drop created objects
        $conn.ExecuteNonQuery("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_invalid') DROP EVENT SESSION [dbatoolsci_session_invalid] ON SERVER;")
        $conn.ExecuteNonQuery("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
    }

    Context "Verifying command works" {
        It "starts the system_health session" {
            $systemhealth | Start-DbaXESession
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should Be $true
        }

        It "does not change state if XE session is already started" {
            if (-Not $systemhealth.IsRunning) {
                $systemhealth.Start()
            }
            $systemhealth | Start-DbaXESession -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $systemhealth.IsRunning | Should Be $true
        }

        It "starts the other XE Sessions when one has an error" {
            # Start system_health and the invalid session
            Start-DbaXESession $server -Session $systemhealth.Name, $dbatoolsciInvalid.Name -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $dbatoolsciInvalid.Refresh()
            $systemhealth.IsRunning | Should Be $true
            $dbatoolsciInvalid.IsRunning | Should Be $false
        }

        It "starts all XE Sessions except the system ones if -AllSessions is used" {
            Start-DbaXESession $server -AllSessions -WarningAction SilentlyContinue
            $systemhealth.Refresh()
            $dbatoolsciValid.Refresh()
            $systemhealth.IsRunning | Should Be $false
            $dbatoolsciValid.IsRunning | Should Be $true
        }

    }
}