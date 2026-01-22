#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaXESession",
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
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag IntegrationTests {
    BeforeAll {
        $sessionName = "dbatoolsci_test_$(Get-Random)"
    }

    AfterAll {
        if ($session) {
            try {
                $session.Drop()
            } catch {
                # Session may not exist or already dropped
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $session = New-DbaXESession -SqlInstance $TestConfig.instance1 -Name $sessionName -EnableException
        }

        It "Returns the documented output type" {
            $session | Should -BeOfType Microsoft.SqlServer.Management.XEvent.Session
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'StartTime',
                'AutoStart',
                'State',
                'Targets',
                'TargetFile',
                'Events',
                'MaxMemory',
                'MaxEventSize'
            )
            $actualProps = $session.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns a session object that can be configured" {
            $session.Name | Should -Be $sessionName
            { $session.AddEvent("sqlserver.sql_statement_completed") } | Should -Not -Throw
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>