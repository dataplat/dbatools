#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "InputObject",
                "NoWait",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context -Skip:(-not (Get-DbaPfDataCollectorSet -CollectorSet RTEvents)) "Verifying command works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # We only run this on Azure as there is this collector set running:
            $null = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns a result with the right computername and name is not null" {
            $results = Start-DbaPfDataCollectorSet -CollectorSet RTEvents

            $WarnVar | Should -BeNullOrEmpty
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context -Skip:(-not (Get-DbaPfDataCollectorSet -CollectorSet RTEvents)) "Output Validation" {
        BeforeAll {
            $null = Stop-DbaPfDataCollectorSet -CollectorSet RTEvents -EnableException
            $result = Start-DbaPfDataCollectorSet -CollectorSet RTEvents -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'Name',
                'State'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the DataCollectorSetObject property available" {
            $result.PSObject.Properties.Name | Should -Contain 'DataCollectorSetObject' -Because "underlying COM object should be accessible"
        }
    }
}