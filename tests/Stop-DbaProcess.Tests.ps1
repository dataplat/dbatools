#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaProcess",
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
                "Spid",
                "ExcludeSpid",
                "Database",
                "Login",
                "Hostname",
                "Program",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "System sessions" {
        BeforeAll {
            # SQL Server refuses to KILL a system session with "Only user processes can be killed", and the
            # command used to try anyway and warn about every one of them. Every instance has system
            # sessions, so any of them shows the behaviour. It matters most on SQL Server 2025, which
            # parks workers such as the DB MIRROR tasks above spid 50 and in user databases, where a call
            # with -Database finds them - and so does every restore that clears the database out first.
            $systemSession = Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle | Where-Object IsSystem | Select-Object -First 1
        }

        It "has a system session to test with" {
            $systemSession | Should -Not -BeNullOrEmpty
            $systemSession.IsSystem | Should -BeTrue
        }

        It "skips a system session that is piped in, without a warning" {
            $results = $systemSession | Stop-DbaProcess
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }

        It "skips a system session that is selected by spid, without a warning" {
            $results = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Spid $systemSession.Spid
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }
    }

    Context "Command execution and functionality" {
        It "kills only this specific process" {
            $fakeapp = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName 'dbatoolsci test app'
            $results = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program 'dbatoolsci test app'
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }

        It "supports piping" {
            $fakeapp = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName 'dbatoolsci test app'
            $results = Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program 'dbatoolsci test app' | Stop-DbaProcess
            $results.Program.Count | Should -Be 1
            $results.Program | Should -Be 'dbatoolsci test app'
            $results.Status | Should -Be 'Killed'
        }
    }
}