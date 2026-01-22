#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbccDropCleanBuffer",
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
                "NoInformationalMessages",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Cmd',
                'Output'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Works correctly" {
        It "returns results" {
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -Be $true
        }

        It "returns the right results for -NoInformationalMessages" {
            $noInfoResult = Invoke-DbaDbccDropCleanBuffer -SqlInstance $TestConfig.InstanceSingle -NoInformationalMessages
            $noInfoResult.Cmd -match "DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS" | Should -Be $true
            $noInfoResult.Output -eq $null | Should -Be $true
        }
    }
}