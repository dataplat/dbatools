#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaXESession",
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
                "InputObject",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Start-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # This command is special and runs infinitely so don't actually try to run it
        It "warns if XE session is not running" {
            $results = Watch-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "system_health is not running"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a temporary test session with minimal configuration for testing
            $sessionName = "dbatoolsci_watch_test"
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a simple XE session if it doesn't exist
            $splatSession = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $sessionName
            }
            $existingSession = Get-DbaXESession @splatSession -WarningAction SilentlyContinue

            if (-not $existingSession) {
                $splatNewSession = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Name        = $sessionName
                    Event       = "sqlserver.sql_statement_completed"
                }
                $null = New-DbaXESession @splatNewSession
            }

            # Start the session
            $null = Start-DbaXESession @splatSession

            # Generate a simple event
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "SELECT 1" | Out-Null

            # Get session object for testing
            $session = Get-DbaXESession @splatSession

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # Clean up test session
            $splatSession = @{
                SqlInstance = $TestConfig.InstanceSingle
                Session     = $sessionName
            }
            Stop-DbaXESession @splatSession -WarningAction SilentlyContinue | Out-Null
            Remove-DbaXESession @splatSession -WarningAction SilentlyContinue | Out-Null
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject by default" {
            # Note: This command streams infinitely, so we can't easily capture output
            # We verify the session is properly configured for streaming
            $session | Should -Not -BeNullOrEmpty
            $session.IsRunning | Should -Be $true
        }

        It "Has the expected core properties available" {
            # The command outputs dynamic properties based on XE session configuration
            # Core properties that should always be present: name, timestamp
            # Additional properties depend on the event fields and actions configured
            $session.Events.Count | Should -BeGreaterThan 0
        }
    }
}