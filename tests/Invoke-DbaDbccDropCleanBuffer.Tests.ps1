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
        $props = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Cmd",
            "Output"
        )
        $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $TestConfig.InstanceSingle
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $p = $result.PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Has the correct properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Cmd",
                "Output"
            )
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has no Select-DefaultView properties" {
            $result.PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
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