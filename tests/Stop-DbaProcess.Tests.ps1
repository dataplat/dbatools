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
    Context "Command execution and functionality" {
        BeforeAll {
            $fakeapp = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci output test"
            $script:outputForValidation = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatoolsci output test"
        }

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

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected properties" {
                $expectedProps = @("SqlInstance", "Spid", "Login", "Host", "Database", "Program", "Status")
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }

            It "Has Status set to Killed" {
                $script:outputForValidation[0].Status | Should -Be "Killed"
            }
        }
    }
}