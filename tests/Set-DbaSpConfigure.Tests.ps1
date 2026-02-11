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
        }

        It "changes the remote query timeout from the original to new value" {
            if ($null -eq $remotequerytimeout) {
                Set-ItResult -Skipped -Because "Remote query timeout value is null"
                return
            }
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $newtimeout
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
    }

    Context "Output validation" {
        BeforeAll {
            $outputConfigTimeout = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout).ConfiguredValue
            $outputNewTimeout = $outputConfigTimeout + 1
            $result = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $outputNewTimeout
        }

        AfterAll {
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName RemoteQueryTimeout -Value $outputConfigTimeout -ErrorAction SilentlyContinue
        }

        It "Returns output of type PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
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
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present on the output object"
            }
        }
    }
}