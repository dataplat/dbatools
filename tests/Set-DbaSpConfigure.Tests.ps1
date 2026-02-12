#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSpConfigure",
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
                "Value",
                "Name",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Set configuration" {
        BeforeAll {
            $remotequerytimeout = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newtimeout = $remotequerytimeout + 1
            # Capture output from first call for output validation
            $script:outputForValidation = $null
        }

        It "changes the remote query timeout from the original to new value" {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $newtimeout
            $script:outputForValidation = $results
            $results.PreviousValue | Should -Be $remotequerytimeout
            $results.NewValue | Should -Be $newtimeout
        }

        It "changes the remote query timeout back to original value" {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $remotequerytimeout
            $results.PreviousValue | Should -Be $newtimeout
            $results.NewValue | Should -Be $remotequerytimeout
        }

        It "returns a warning when if the new value is the same as the old"  {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $remotequerytimeout -WarningVariable warning -WarningAction SilentlyContinue
            $warning -match "existing" | Should -Be $true
        }

        Context "Output validation" {
            It "Returns output of type PSCustomObject" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
            }

            It "Has the expected properties" {
                $expectedProps = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "ConfigName",
                    "PreviousValue",
                    "NewValue"
                )
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present on the output object"
                }
            }
        }
    }
}