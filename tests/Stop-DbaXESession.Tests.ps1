#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "AllSessions",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        # Create a valid session and start it
        $server.Query("CREATE EVENT SESSION [dbatoolsci_session_valid] ON SERVER ADD EVENT sqlserver.lock_acquired;")
        $dbatoolsciValid = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session dbatoolsci_session_valid
        $dbatoolsciValid.Start()
        # Record the Status of all sessions
        $allSessions = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle
    }
    BeforeEach {
        $dbatoolsciValid.Refresh()
        if (-Not $dbatoolsciValid.IsRunning) {
            $dbatoolsciValid.Start()
        }
    }
    AfterAll {
        # Set the Status of all session back to what they were before the test
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

        # Drop created objects
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name = 'dbatoolsci_session_valid') DROP EVENT SESSION [dbatoolsci_session_valid] ON SERVER;")
    }

    Context "Command execution and functionality" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        }

        It "stops the system_health session" {
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

    Context "Output Validation" {
        BeforeAll {
            $result = Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $dbatoolsciValid.Name -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.XEvent.Session]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'State',
                'IsRunning',
                'StartTime',
                'DefinitionFileLocation',
                'MaxMemory',
                'EventRetentionMode'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}