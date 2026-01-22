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
    Context "Output Validation" {
        BeforeAll {
            $fakeapp = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName 'dbatoolsci output test app'
            $result = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program 'dbatoolsci output test app' -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'SqlInstance',
                'Spid',
                'Login',
                'Host',
                'Database',
                'Program',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Status property confirms successful termination" {
            $result.Status | Should -Be 'Killed'
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