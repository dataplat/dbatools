#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESession",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle
            $results.Count -gt 1 | Should -Be $true
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $results.Name -eq "system_health" | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType Microsoft.SqlServer.Management.XEvent.Session
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
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected added NoteProperties" {
            $expectedNoteProps = @(
                'Session',
                'RemoteTargetFile',
                'Parent',
                'Store'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedNoteProps) {
                $actualProps | Should -Contain $prop -Because "NoteProperty '$prop' should be added by the command"
            }
        }

        It "Has Status property with valid values" {
            $result.Status | Should -BeIn @('Running', 'Stopped')
        }
    }
}